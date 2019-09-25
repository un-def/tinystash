local constants = require('app.constants')
local utils = require('app.utils')
local base_uploader = require('app.uploader.base')


local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local req_socket = ngx.req.socket

local CHUNK_SIZE = constants.CHUNK_SIZE
local DOWNSTREAM_TIMEOUT = constants.DOWNSTREAM_TIMEOUT
local TG_MAX_FILE_SIZE = constants.TG_MAX_FILE_SIZE

local format_error = utils.format_error


local _M = setmetatable({}, base_uploader)

_M.__index = _M

_M.new = function(_, upload_type, chat_id, headers)
  -- sets:
  --    self.media_type: string (via set_media_type)
  local content_length = headers['content-length']
  if not content_length then
    return nil, ngx_HTTP_BAD_REQUEST, 'no content-length header'
  end
  content_length = tonumber(content_length)
  if not content_length then
    return nil, ngx_HTTP_BAD_REQUEST, 'invalid content-length header'
  elseif content_length <= 0 then
    return nil, ngx_HTTP_BAD_REQUEST, 'content-length header value <= 0'
  elseif content_length > TG_MAX_FILE_SIZE then
    return nil, 413, 'declared content-length is too big for getFile API method'
  end
  local instance = setmetatable({
    upload_type = upload_type,
    chat_id = chat_id,
    expected_content_length = content_length,
  }, _M)
  instance:set_media_type(headers['content-type'])
  instance:set_filename(instance.media_type)
  return instance
end

_M.run = function(self)
  -- sets:
  --    self.bytes_uploaded: int (via upload)
  --    self.boundary: string
  --    self.conn: http connection (via upload)
  local sock, err = req_socket()
  if not sock then
    return nil, ngx_HTTP_BAD_REQUEST, err
  end
  sock:settimeout(DOWNSTREAM_TIMEOUT)
  self.request_socket = sock
  self:set_boundary()
  local content_iterator = self:get_content_iterator()
  local file_object, err_code
  file_object, err_code, err = self:upload(content_iterator)
  if not file_object then
    return nil, err_code, err
  end
  if self.bytes_uploaded ~= self.expected_content_length then
    err = ('incorrect content-length: declared %s, uploaded %s'):format(
      self.expected_content_length, self.bytes_uploaded)
    return nil, ngx_HTTP_BAD_REQUEST, err
  end
  return file_object
end

_M.get_content_iterator = function(self)
  local sock = self.request_socket
  local done = false
  return function()
    if done then
      return nil
    end
    -- err:
    --  'closed' -- downstream connection closed (it's maybe ok or not)
    --  'timeout' -- downstream read timeout (it's definitely not ok)
    -- we do not check err and finish uploading to telegram anyway
    -- because we will compare actual bytes_uploaded with
    -- declared expected_content_length later
    local data, err, partial = sock:receive(CHUNK_SIZE)
    if data then
      return data
    elseif partial == '' then
      return nil
    elseif partial then
      done = true
      return partial
    else
      return nil, format_error('socket error', err)
    end
  end
end

return _M