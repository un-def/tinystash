local constants = require('app.constants')
local utils = require('app.utils')
local base_uploader = require('app.uploader.base')


local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY
local req_socket = ngx.req.socket

local CHUNK_SIZE = constants.CHUNK_SIZE

local log = utils.log


local FIELD_NAME_FILE = 'file'
local FIELD_NAME_CSRFTOKEN = 'csrftoken'


local _M = setmetatable({}, base_uploader)

_M.__index = _M

_M.FIELD_NAME_FILE = FIELD_NAME_FILE
_M.FIELD_NAME_CSRFTOKEN = FIELD_NAME_CSRFTOKEN

_M.new = function(_, upload_type, chat_id, headers)
  local content_length = headers['content-length']
  if not content_length then
    return nil, 'no content-length header'
  end
  content_length = tonumber(content_length)
  if not content_length then
    return nil, 'invalid content-length header'
  elseif content_length <= 0 then
    return nil, 'content-length header value <= 0'
  end
  local instance = setmetatable({
    upload_type = upload_type,
    chat_id = chat_id,
    expected_content_length = content_length,
  }, _M)
  instance:set_media_type(headers['content-type'])
  return instance
end

_M.run = function(self)
  -- returns:
  --   if ok: TG API object (Document/Video/...) table with mandatory 'file_id' field
  --   if error: nil, error_code, error_text?
  -- sets:
  --  self.media_type: string (via set_media_type)
  --  self.boundary: string
  --  self.conn: http connection (via upload)
  --  self.bytes_uploaded: int (via upload)
  local sock, err = req_socket()
  if not sock then
    return nil, ngx_HTTP_BAD_REQUEST, err
  end
  self.request_socket = sock
  self:set_boundary()
  local content_iterator = self:get_content_iterator()
  local file_object
  file_object, err = self:upload(content_iterator)
  if not file_object then
    return nil, ngx_HTTP_BAD_GATEWAY, err
  end
  return file_object
end

_M.get_content_iterator = function(self)
  local sock = self.request_socket
  local done = false
  return function()
    if done then
      log('end of request body')
      return nil
    end
    local data, err, partial = sock:receive(CHUNK_SIZE)
    if data then
      return data
    elseif partial == '' then
      log('end of request body')
      return nil
    elseif partial then
      done = true
      return partial
    else
      log('read body error: %s', err)
      return nil
    end
  end
end

return _M
