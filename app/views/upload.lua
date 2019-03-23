local upload = require('resty.upload')
local template = require('resty.template')
local random_bytes = require('resty.random').bytes
local to_hex = require('resty.string').to_hex

local tinyid = require('app.tinyid')
local tg = require('app.tg')
local utils = require('app.utils')
local CHUNK_SIZE = require('app.constants').CHUNK_SIZE
local render_link_factory = require('app.views.helpers').render_link_factory
local tg_upload_chat_id = require('config.app').tg.upload_chat_id

local yield = coroutine.yield

local log = utils.log
local exit = utils.exit
local parse_media_type = utils.parse_media_type
local normalize_media_type = utils.normalize_media_type
local get_media_type_id = utils.get_media_type_id
local guess_extension = utils.guess_extension

local prepare_connection = tg.prepare_connection
local request_tg_server = tg.request_tg_server


local format_error = function(preamble, error)
  if not error then
    return preamble
  end
  return ('%s: %s'):format(preamble, error)
end


local check_is_file_part = function(content_disposition)
  if content_disposition:find('[ ;]name="file"') then
    return true
  end
  return false
end


local uploader_meta = {}
uploader_meta.__index = uploader_meta


local prepare_uploader = function(upload_type, chat_id)
  local form, err = upload:new(CHUNK_SIZE)
  if not form then
    return nil, err
  end
  form:set_timeout(1000) -- 1 sec
  return setmetatable({
    upload_type = upload_type,
    chat_id = chat_id,
    form = form,
  }, uploader_meta)
end


uploader_meta.close = function(self)
  if self.conn then
    self.conn:set_keepalive()
  end
end


local yield_chunk = function(bytes)
  -- yield chunked transfer encoding chunk
  if bytes == nil then bytes = '' end
  yield(('%X\r\n%s\r\n'):format(#bytes, bytes))
end


uploader_meta.upload_body_coro = function(self, boundary, media_type, initial)
  -- send nothing on first call (priming)
  yield(nil)
  local sep = ('--%s\r\n'):format(boundary)
  local ext = guess_extension{media_type = media_type, exclude_dot = true} or 'bin'
  local filename = ('%s.%s'):format(to_hex(random_bytes(16)), ext)
  yield_chunk(sep)
  yield_chunk('content-disposition: form-data; name="chat_id"\r\n\r\n')
  yield_chunk(('%s\r\n'):format(self.chat_id))
  yield_chunk(sep)
  yield_chunk(('content-disposition: form-data; name="document"; filename="%s"\r\n'):format(filename))
  yield_chunk(('content-type: %s\r\n\r\n'):format(media_type))
  if initial then
    -- first chunk of the file
    yield_chunk(initial)
  end
  local form = self.form
  local token, data, err
  while true do
    token, data, err = form:read()
    if not token then
      log(ngx.ERR, 'failed to read next form chunk: %s', err)
      break
    elseif token == 'body' then
      yield_chunk(data)
    elseif token == 'part_end' then
      break
    else
      log(ngx.ERR, 'unexpected token: %s', token)
      break
    end
  end
  yield_chunk(('\r\n--%s--\r\n'):format(boundary))
  yield_chunk(nil)
end


uploader_meta.get_upload_body_iterator = function(self, boundary, media_type, initial)
  local iterator = coroutine.wrap(self.upload_body_coro)
  -- pass function arguments in the first call (priming)
  iterator(self, boundary, media_type, initial)
  return iterator
end


uploader_meta.run = function(self)
  -- returns:
  --   if ok: table with file_id and media_type keys
  --   if error: nil, error_code, error_text?
  local res, err_code, err
  while true do
    res, err_code, err = self:maybe_upload_part()
    if not res then
      return nil, err_code, err
    elseif res.file_id then
      return res
    end
  end
end


uploader_meta.maybe_upload_part = function(self)
  -- returns:
  --   if part has no file: empty table
  --   if file has been uploaded: table with file_id and media_type keys
  --   if error (any): nil, error_code, error_text?
  local form = self.form
  local media_type
  if self.upload_type == 'text' then
    media_type = 'text/plain'
  end
  -- true if we found a file
  local is_file_part = false
  local file_id, err
  local token, data
  while true do
    token, data, err = form:read()
    if not token then
      return nil, ngx.HTTP_BAD_REQUEST, err
    elseif token == 'header' then
      if type(data) ~= 'table' then
        return nil, ngx.HTTP_BAD_REQUEST, 'invalid header'
      end
      local header = data[1]:lower()
      local value = data[2]
      if header == 'content-type' and not media_type then
        media_type = value
      elseif header == 'content-disposition' then
        is_file_part = check_is_file_part(value)
      end
    elseif token == 'body' and is_file_part then
      if not media_type then
        media_type = 'application/octet-stream'
      else
        media_type = normalize_media_type(media_type)
      end
      log('media type: %s', media_type)
      file_id, err = self:upload(media_type, data)
      if not file_id then
        return nil, ngx.HTTP_INTERNAL_SERVER_ERROR, err
      end
      return {
        file_id = file_id,
        media_type = media_type,
      }
    elseif token == 'part_end' then
      return {}
    elseif token == 'eof' then
      return nil, ngx.HTTP_BAD_REQUEST, 'no input'
    end
  end
end


uploader_meta.upload = function(self, media_type, initial)
  -- media_type: string or nil
  -- initial: string or nil, first chunk of file
  -- returns:
  --  if ok: file_id
  --  if error: nil, err
  local boundary = 'BNDR-' .. to_hex(random_bytes(32))

  local conn, res, err
  conn, err = prepare_connection()
  if not conn then
    return nil, err
  end
  self.conn = conn

  local upload_body_iterator = self:get_upload_body_iterator(boundary, media_type, initial)

  local params = {
    path = '/bot%s/sendDocument',
    method = 'POST',
    headers = {
      ['content-type'] = 'multipart/form-data; boundary=' .. boundary,
      ['transfer-encoding'] = 'chunked',
    },
    body = upload_body_iterator,
  }
  res, err = request_tg_server(conn, params, true)
  if not res then
    return nil, format_error('tg api request error', err)
  end
  if not res.ok then
    return nil, format_error('tg api response is not "ok"', res.description)
  end
  local document = res.result and res.result.document
  if not document or not document.file_id then
    return nil, 'tg api response has no document file_id'
  end
  return document.file_id
end


return {

  initial = function(upload_type)
    if not tg_upload_chat_id then
      exit(ngx.HTTP_NOT_FOUND)
    end
    if upload_type == '' then
      upload_type = 'file'
    end
    return upload_type
  end,

  GET = function(upload_type)
    template.render('web/upload.html', {
      upload_type = upload_type,
    })
  end,

  POST = function(upload_type)
    ngx.header['content-type'] = 'text/plain'
    local uploader, err = prepare_uploader(upload_type, tg_upload_chat_id)
    if not uploader then
      log(ngx.ERR, 'failed to init uploader: %s', err)
      exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    local res, err_code
    res, err_code, err = uploader:run()
    uploader:close()
    if not res then
      exit(err_code, err)
    end
    local media_type = res.media_type
    local media_type_id = get_media_type_id(media_type)
    if not media_type_id then
      local media_type_table = parse_media_type(media_type)
      if media_type_table[1] == 'text' then
        media_type_id = get_media_type_id('text/plain')
      end
    end
    local tiny_id
    tiny_id, err = tinyid.encode{
      file_id = res.file_id,
      media_type_id = media_type_id,
    }
    if not tiny_id then
      log(ngx.ERR, 'failed to encode tiny_id: %s', err)
      exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    ngx.redirect(render_link_factory(tiny_id)('ln'), ngx.HTTP_SEE_OTHER)
  end

}
