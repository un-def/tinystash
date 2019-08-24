local upload = require('resty.upload')

local tg = require('app.tg')
local utils = require('app.utils')
local constants = require('app.constants')


local yield = coroutine.yield
local ngx_null = ngx.null
local ngx_ERR = ngx.ERR
local ngx_HTTP_FORBIDDEN = ngx.HTTP_FORBIDDEN
local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY

local log = utils.log
local generate_random_hex_string = utils.generate_random_hex_string
local normalize_media_type = utils.normalize_media_type
local guess_extension = utils.guess_extension

local CHUNK_SIZE = constants.CHUNK_SIZE

local prepare_connection = tg.prepare_connection
local request_tg_server = tg.request_tg_server
local get_file_from_message = tg.get_file_from_message


local FIELD_NAME_FILE = 'file'
local FIELD_NAME_CSRFTOKEN = 'csrftoken'


local format_error = function(preamble, error)
  if not error then
    return preamble
  end
  return ('%s: %s'):format(preamble, error)
end


local yield_chunk = function(bytes)
  -- yield chunked transfer encoding chunk
  if bytes == nil then bytes = '' end
  yield(('%X\r\n%s\r\n'):format(#bytes, bytes))
end


local get_form_field_name = function(content_disposition)
  return content_disposition:match('[ ;]name="([^"]+)"')
end


local _M = {
  FIELD_NAME_FILE = FIELD_NAME_FILE,
  FIELD_NAME_CSRFTOKEN = FIELD_NAME_CSRFTOKEN,
}


local uploader_meta = {}
uploader_meta.__index = uploader_meta


_M.new = function(_, upload_type, chat_id, csrftoken)
  local form, err = upload:new(CHUNK_SIZE)
  if not form then
    return nil, err
  end
  form:set_timeout(1000) -- 1 sec
  return setmetatable({
    upload_type = upload_type,
    chat_id = chat_id,
    csrftoken = csrftoken,
    form = form,
    -- bytes_uploaded = nil | number (set by upload_body_coro)
    -- media_type = nil | string (set by run)
  }, uploader_meta)
end


uploader_meta.close = function(self)
  if self.conn then
    self.conn:set_keepalive()
  end
end

uploader_meta.run = function(self)
  -- returns:
  --   if ok: TG API object (Document/Video/...) table with mandatory 'file_id' field
  --   if error: nil, error_code, error_text?
  -- sets:
  --  self.media_type: string (via set_media_type)
  --  self.boundary: string (via set_boundary)
  --  self.conn: http connection (via upload)
  --  self.bytes_uploaded: int (via upload)
  local file_object, csrftoken
  local res, err
  while true do
    res, err = self:handle_form_field()
    if not res then
      log(err)
      return nil, ngx_HTTP_BAD_REQUEST, err
    elseif res == ngx_null then
      log('end of form')
      break
    else
      local field_name, media_type, initial_data = unpack(res)
      if field_name == FIELD_NAME_CSRFTOKEN then
        csrftoken = initial_data
        if csrftoken ~= self.csrftoken then
          return nil, ngx_HTTP_FORBIDDEN, 'invalid csrf token'
        end
      elseif field_name == FIELD_NAME_FILE then
        if initial_data:len() == 0 then
          return nil, ngx_HTTP_BAD_REQUEST, 'empty file'
        end
        self:set_media_type(media_type)
        self:set_boundary()
        local upload_body_iterator = self:get_upload_body_iterator(initial_data)
        file_object, err = self:upload(upload_body_iterator)
        if not file_object then
          return nil, ngx_HTTP_BAD_GATEWAY, err
        end
      else
        return nil, ngx_HTTP_BAD_REQUEST, format_error('unexpected form field', field_name)
      end
    end
  end
  if not csrftoken then
    return nil, ngx_HTTP_FORBIDDEN, 'no csrf token'
  elseif csrftoken ~= self.csrftoken then
    return nil, ngx_HTTP_FORBIDDEN, 'invalid csrf token'
  elseif not file_object then
    return nil, ngx_HTTP_BAD_REQUEST, 'no file'
  end
  return file_object
end

uploader_meta.set_media_type = function(self, media_type)
  -- media_type: string or nil
  -- sets:
  --  self.media_type
  if self.upload_type == 'text' then
    media_type = 'text/plain'
  elseif not media_type then
    media_type = 'application/octet-stream'
  else
    media_type = normalize_media_type(media_type)
  end
  log('media type: %s', media_type)
  self.media_type = media_type
end

uploader_meta.set_boundary = function(self)
  -- sets:
  --  self.media_type
  local boundary = 'BNDR-' .. generate_random_hex_string(32)
  self.boundary = boundary
end

uploader_meta.handle_form_field = function(self)
  -- returns:
  --  if eof: ngx.null
  --  if body (any): first chunk of body ("initial_data")
  --  if error (any): nil, error_code, error_text?
  local form = self.form
  local field_name, media_type
  local token, data, err
  while true do
    token, data, err = form:read()
    -- 'part_end' tokens are ignored
    if not token then
      return nil, err
    elseif token == 'eof' then
      return ngx_null
    elseif token == 'header' then
      if type(data) ~= 'table' then
        return nil, 'invalid form-data part header'
      end
      local header = data[1]:lower()
      local value = data[2]
      if header == 'content-type' then
        media_type = value
      elseif header == 'content-disposition' then
        field_name = get_form_field_name(value)
      end
    elseif token == 'body' and field_name then
      return {field_name, media_type, data}
    end
  end
end

uploader_meta.upload = function(self, upload_body_iterator)
  -- upload_body_iterator: iterator function producing body chunks
  -- returns:
  --  if ok: table -- TG API object (Document/Video/...) table
  --  if error: nil, err
  -- sets:
  --  self.conn: http connection
  --  self.bytes_uploaded: int (via upload_body_iterator)
  local conn, res, err
  conn, err = prepare_connection()
  if not conn then
    return nil, err
  end
  self.conn = conn
  local params = {
    path = '/bot%s/sendDocument',
    method = 'POST',
    headers = {
      ['content-type'] = 'multipart/form-data; boundary=' .. self.boundary,
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
  if not res.result then
    return nil, 'tg api response has no "result"'
  end
  local file
  file, err = get_file_from_message(res.result)
  if not file then
    return nil, err
  end
  local file_object = file.object
  if not file_object.file_id then
    return nil, 'tg api response has no file_id'
  end
  return file_object
end

uploader_meta.get_upload_body_iterator = function(self, initial)
  local iterator = coroutine.wrap(self.upload_body_coro)
  -- pass function arguments in the first call (priming)
  iterator(self, initial)
  return iterator
end

uploader_meta.upload_body_coro = function(self, initial)
  -- sets:
  --   self.bytes_uploaded: number
  -- send nothing on first call (iterator priming)
  yield(nil)
  local media_type = self.media_type
  local boundary = self.boundary
  local sep = ('--%s\r\n'):format(boundary)
  local ext = guess_extension{media_type = media_type, exclude_dot = true} or 'bin'
  local filename = ('%s.%s'):format(generate_random_hex_string(16), ext)
  yield_chunk(sep)
  yield_chunk('content-disposition: form-data; name="chat_id"\r\n\r\n')
  yield_chunk(('%s\r\n'):format(self.chat_id))
  yield_chunk(sep)
  yield_chunk(('content-disposition: form-data; name="document"; filename="%s"\r\n'):format(filename))
  yield_chunk(('content-type: %s\r\n\r\n'):format(media_type))
  local bytes_uploaded = 0
  if initial then
    -- first chunk of the file
    yield_chunk(initial)
    bytes_uploaded = bytes_uploaded + #initial
  end
  local form = self.form
  local token, data, err
  while true do
    token, data, err = form:read()
    if not token then
      log(ngx_ERR, 'failed to read next form chunk: %s', err)
      break
    elseif token == 'body' then
      yield_chunk(data)
      bytes_uploaded = bytes_uploaded + #data
    elseif token == 'part_end' then
      break
    else
      log(ngx_ERR, 'unexpected token: %s', token)
      break
    end
  end
  yield_chunk(('\r\n--%s--\r\n'):format(boundary))
  yield_chunk(nil)
  self.bytes_uploaded = bytes_uploaded
end

return _M
