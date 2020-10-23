local formdata = require('httoolsp.formdata')

local tg = require('app.tg')
local utils = require('app.utils')
local constants = require('app.constants')
local DEFAULT_TYPE = require('app.mediatypes').DEFAULT_TYPE


local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO

local prepare_connection = tg.prepare_connection
local request_tg_server = tg.request_tg_server
local get_file_from_message = tg.get_file_from_message

local log = utils.log
local guess_extension = utils.guess_extension
local escape_ext = utils.escape_ext
local generate_random_hex_string = utils.generate_random_hex_string


local not_implemented = function()
  error('not implemented')
end


local _M = {}

_M.__index = _M

_M.MAX_FILE_SIZE = constants.TG_MAX_FILE_SIZE

_M.new = function()
  -- params:
  --    upload_type: string -- 'file' or 'text'
  --    chat_id: integer
  --    headers: table -- request headers
  -- returns:
  --    if ok: table -- uploader instance
  --    if error: nil, error_code, error_text?
  -- sets:
  --    ...
  -- note:
  --    error_text will be sent in a http response,
  --    do not expose sensitive data/errors!
  not_implemented()
end

_M.run = function()
  -- params:
  --    none
  -- returns:
  --    if ok: TG API object (Document/Video/...) table with mandatory 'file_id' field
  --    if error: nil, error_code, error_text?
  -- sets:
  --    self.media_type: string
  --    self.bytes_uploaded: integer
  --    ...
  --    error_text will be sent in a http response,
  --    do not expose sensitive data/errors!
  not_implemented()
end

_M.close = function(self)
  if self.conn then
    self.conn:set_keepalive()
  end
end

_M.upload = function(self, content)
  -- params:
  --    content: string or function -- body or iterator producing content chunks
  -- returns:
  --    if ok: TG API object (Document/Video/...) table with mandatory 'file_id' field
  --    if error: nil, error_code
  -- sets:
  --    self.conn: table -- http connection
  --    self.bytes_uploaded: int (via _get_content_iterator closure)
  local conn, res, err
  conn, err = prepare_connection()
  if not conn then
    log(ngx_ERR, 'tg api connection error: %s', err)
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  self.conn = conn
  local media_type = self.media_type
  -- avoid automatic gif -> mp4 conversion by tricking Telegram
  if media_type == 'image/gif' then
    -- replace actual content type with generic one
    media_type = DEFAULT_TYPE
  end
  local fd = formdata.new()
  fd:set('chat_id', tostring(self.chat_id))
  fd:set('document', self:_get_content_iterator(content), media_type, self.filename)
  local params = {
    path = '/bot%s/sendDocument',
    method = 'POST',
    headers = {
      ['content-type'] = 'multipart/form-data; boundary=' .. fd:get_boundary(),
      ['transfer-encoding'] = 'chunked',
    },
    body = self:_get_chunked_body_iterator(fd:iterator()),
  }
  res, err = request_tg_server(conn, params, true)
  -- _get_content_iterator closure sets self._content_iterator_error to indicate error
  -- while reading content from request
  if self._content_iterator_error then
    return nil, ngx_HTTP_BAD_REQUEST
  end
  if not res then
    log(ngx_ERR, 'tg api request error: %s', err)
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  if not res.ok then
    log(ngx_INFO, 'tg api response is not "ok": %s', res.description)
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  if not res.result then
    log(ngx_INFO, 'tg api response has no "result"')
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  local file
  file, err = get_file_from_message(res.result)
  if not file then
    log(ngx_INFO, err)
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  local file_object = file.object
  if not file_object.file_id then
    log(ngx_INFO, 'tg api response has no "file_id"')
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  return file_object
end

_M._get_content_iterator = function(self, content)
  -- params:
  --    content: string or function -- body or iterator producing body chunks
  -- returns:
  --    iterator function that controls uploaded file size and sets self.bytes_uploaded
  if type(content) == 'function' then
    return function()
      local bytes_uploaded = self.bytes_uploaded or 0
      if self:is_max_file_size_exceeded(bytes_uploaded) then
        log(ngx_INFO, 'content iterator produced more bytes than MAX_FILE_SIZE, breaking consuming')
        return nil
      end
      local chunk, err = content()
      if err then
        log(ngx_INFO, 'content iterator error: %s', err)
        self._content_iterator_error = err
        return nil
      end
      if not chunk then
        log('end of content')
        return nil
      end
      self.bytes_uploaded = bytes_uploaded + #chunk
      return chunk
    end
  else
    local done = false
    return function()
      if done then
        self.bytes_uploaded = #content
        return nil
      end
      done = true
      return content
    end
  end
end

_M._get_chunked_body_iterator = function(_, iterator)
  -- params:
  --    iterator: iterator producing body chunks
  -- returns:
  --    iterator producing `transfer-encoding: chunked` chunks
  local done = false
  return function()
    if done then
      return nil
    end
    local chunk = iterator()
    if not chunk then
      done = true
      chunk = ''
    end
    return ('%X\r\n%s\r\n'):format(#chunk, chunk)
  end
end

_M.is_max_file_size_exceeded = function(self, file_size)
  return file_size > self.MAX_FILE_SIZE
end

_M.set_media_type = function(self, media_type)
  -- params:
  --    media_type: string or nil
  -- sets:
  --    self.media_type
  if self.upload_type == 'text' then
    media_type = 'text/plain'
  elseif not media_type then
    media_type = DEFAULT_TYPE
  end
  log('content media type: %s', media_type)
  self.media_type = media_type
end

_M.set_filename = function(self, media_type, filename)
  -- params:
  --    media_type: string
  --    filename: string or nil
  -- sets:
  --    self.filename
  if not filename then
    local ext = guess_extension{media_type = media_type, exclude_dot = true} or 'bin'
    filename = ('%s-%s.%s'):format(
      media_type:gsub('/', '_'), generate_random_hex_string(16), ext)
    log('generated filename: %s', filename)
  else
    log('original filename: %s', filename)
    filename = filename:gsub('[%s";\\]', '_')
  end
  self.filename = escape_ext(filename)
end

return _M
