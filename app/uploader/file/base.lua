local formdata = require('httoolsp.formdata')

local tg = require('app.tg')
local utils = require('app.utils')
local DEFAULT_TYPE = require('app.mediatypes').DEFAULT_TYPE

local base_uploader = require('app.uploader.base')

local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO

local prepare_connection = tg.prepare_connection
local request_tg_server = tg.request_tg_server
local get_file_from_message = tg.get_file_from_message

local log = utils.log


local _M = setmetatable({}, base_uploader)

_M.__index = _M

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

return _M
