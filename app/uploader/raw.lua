local constants = require('app.constants')
local utils = require('app.utils')
local base_uploader = require('app.uploader.base')

local req_socket = ngx.req.socket
local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_ERR = ngx.ERR

local CHUNK_SIZE = constants.CHUNK_SIZE
local DOWNSTREAM_TIMEOUT = constants.DOWNSTREAM_TIMEOUT

local log = utils.log
local format_error = utils.format_error

local maximum_file_size_err = (
  'declared content-length is too big - maximum file size is %s'
):format(base_uploader.MAX_FILE_SIZE)


local _M = setmetatable({}, base_uploader)

_M.__index = _M

_M.new = function(_, upload_type, chat_id, headers)
  -- sets:
  --    self.media_type: string (via set_media_type)
  local transfer_encoding = headers['transfer-encoding']
  if transfer_encoding ~= nil then
    -- nginx will terminate a request early with 501 Not Implemented
    -- if transfer-encoding is not supported or if the client sends
    -- invalid chunks (for chunked encoding), therefore,
    -- this check is never actually performed
    return nil, 501, transfer_encoding .. ' is not supported'
  end
  local content_length = headers['content-length']
  if not content_length then
    return nil, 411, 'no content-length header'
  end
  content_length = tonumber(content_length)
  if not content_length then
    return nil, ngx_HTTP_BAD_REQUEST, 'invalid content-length header'
  elseif content_length <= 0 then
    return nil, ngx_HTTP_BAD_REQUEST, 'content-length header value is 0'
  elseif base_uploader:is_max_file_size_exceeded(content_length) then
    return nil, 413, maximum_file_size_err
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
    log(ngx_ERR, 'downstream socket error: %s', err)
    return nil, ngx_HTTP_BAD_REQUEST
  end
  sock:settimeout(DOWNSTREAM_TIMEOUT)
  self.request_socket = sock
  self:set_boundary()
  local content_iterator = self:get_content_iterator()
  local file_object, err_code
  file_object, err_code = self:upload(content_iterator)
  if not file_object then
    return nil, err_code
  end
  if self.bytes_uploaded ~= self.expected_content_length then
    err = ('incorrect content-length - declared %s, uploaded %s'):format(
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
