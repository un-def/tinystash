local tg = require('app.tg')
local utils = require('app.utils')


local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY
local yield = coroutine.yield

local prepare_connection = tg.prepare_connection
local request_tg_server = tg.request_tg_server
local get_file_from_message = tg.get_file_from_message

local log = utils.log
local format_error = utils.format_error
local guess_extension = utils.guess_extension
local normalize_media_type = utils.normalize_media_type
local generate_random_hex_string = utils.generate_random_hex_string


local yield_chunk = function(bytes)
  -- yield chunked transfer encoding chunk
  if bytes == nil then bytes = '' end
  yield(('%X\r\n%s\r\n'):format(#bytes, bytes))
end


local not_implemented = function()
  error('not implemented')
end


local _M = {}

_M.__index = _M

_M.new = function()
  -- params:
  --    upload_type: string -- 'file' or 'text'
  --    chat_id: integer
  --    headers: table -- request headers
  -- returns:
  --    if ok: table -- uploader instance
  --    if error: nil, error_code, error_text
  -- sets:
  --    ...
  not_implemented()
end

_M.run = function()
  -- params:
  --    none
  -- returns:
  --    if ok: TG API object (Document/Video/...) table with mandatory 'file_id' field
  --    if error: nil, error_code, error_text
  -- sets:
  --    self.media_type: string
  --    self.bytes_uploaded: integer
  --    ...
  not_implemented()
end

_M.close = function(self)
  if self.conn then
    self.conn:set_keepalive()
  end
end

_M.upload = function(self, content)
  -- params:
  --    content: string or function -- body or iterator producing body chunks
  -- returns:
  --    if ok: TG API object (Document/Video/...) table with mandatory 'file_id' field
  --    if error: nil, error_code, error_text
  -- sets:
  --    self.conn: table -- http connection
  --    self.bytes_uploaded: int (via upload_body_coro)
  local conn, res, err
  conn, err = prepare_connection()
  if not conn then
    return nil, ngx_HTTP_BAD_GATEWAY, err
  end
  self.conn = conn
  local upload_body_iterator = coroutine.wrap(self.upload_body_coro)
  -- pass function arguments in the first call (priming)
  upload_body_iterator(self, content)
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
  -- upload_body_iterator sets self._upload_body_coro_error to indicate error
  -- while reading content from request
  if self._upload_body_coro_error then
    return nil, ngx_HTTP_BAD_REQUEST, self._upload_body_coro_error
  end
  if not res then
    return nil, ngx_HTTP_BAD_GATEWAY, format_error('tg api request error', err)
  end
  if not res.ok then
    return nil, ngx_HTTP_BAD_GATEWAY, format_error('tg api response is not "ok"', res.description)
  end
  if not res.result then
    return nil, ngx_HTTP_BAD_GATEWAY, 'tg api response has no "result"'
  end
  local file
  file, err = get_file_from_message(res.result)
  if not file then
    return nil, ngx_HTTP_BAD_GATEWAY, err
  end
  local file_object = file.object
  if not file_object.file_id then
    return nil, ngx_HTTP_BAD_GATEWAY, 'tg api response has no file_id'
  end
  return file_object
end


_M.upload_body_coro = function(self, content)
  -- params:
  --    content: string or function -- body or iterator producing body chunks
  -- sets:
  --    self.bytes_uploaded: integer
  --    self._upload_body_coro_error: string -- error message (if any)
  --
  -- send nothing on first call (iterator priming)
  yield(nil)
  local media_type = self.media_type
  local boundary = self.boundary
  local sep = ('--%s\r\n'):format(boundary)
  yield_chunk(sep)
  yield_chunk('content-disposition: form-data; name="chat_id"\r\n\r\n')
  yield_chunk(('%s\r\n'):format(self.chat_id))
  yield_chunk(sep)
  yield_chunk(('content-disposition: form-data; name="document"; filename="%s"\r\n'):format(self.filename))
  yield_chunk(('content-type: %s\r\n\r\n'):format(media_type))
  local bytes_uploaded = 0
  if type(content) == 'function' then
    while true do
      local chunk, err = content()
      if err then
        self._upload_body_coro_error = format_error('content iterator error', err)
        break
      end
      if not chunk then
        log('end of content')
        break
      end
      yield_chunk(chunk)
      bytes_uploaded = bytes_uploaded + #chunk
    end
  else
    yield_chunk(content)
    bytes_uploaded = #content
  end
  yield_chunk(('\r\n--%s--\r\n'):format(boundary))
  yield_chunk(nil)
  self.bytes_uploaded = bytes_uploaded
end

_M.set_media_type = function(self, media_type)
  -- params:
  --    media_type: string or nil
  -- sets:
  --    self.media_type
  if self.upload_type == 'text' then
    media_type = 'text/plain'
  elseif not media_type then
    media_type = 'application/octet-stream'
  else
    media_type = normalize_media_type(media_type)
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
    filename = ('%s.%s'):format(generate_random_hex_string(16), ext)
    log('generated filename: %s', filename)
  else
    log('original filename: %s', filename)
    filename = filename:gsub('[%s";\\]', '_')
  end
  self.filename = filename
end

_M.set_boundary = function(self)
  -- sets:
  --    self.boundary: string
  self.boundary = 'BNDR-' .. generate_random_hex_string(32)
end

return _M
