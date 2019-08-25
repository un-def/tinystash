local upload = require('resty.upload')

local utils = require('app.utils')
local constants = require('app.constants')
local base_uploader = require('app.uploader.base')


local yield = coroutine.yield
local ngx_null = ngx.null
local ngx_ERR = ngx.ERR
local ngx_HTTP_FORBIDDEN = ngx.HTTP_FORBIDDEN
local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY

local log = utils.log
local format_error = utils.format_error
local generate_random_hex_string = utils.generate_random_hex_string
local guess_extension = utils.guess_extension

local CHUNK_SIZE = constants.CHUNK_SIZE


local FIELD_NAME_FILE = 'file'
local FIELD_NAME_CSRFTOKEN = 'csrftoken'


local yield_chunk = function(bytes)
  -- yield chunked transfer encoding chunk
  if bytes == nil then bytes = '' end
  yield(('%X\r\n%s\r\n'):format(#bytes, bytes))
end


local get_form_field_name = function(content_disposition)
  return content_disposition:match('[ ;]name="([^"]+)"')
end


local _M = setmetatable({}, base_uploader)

_M.__index = _M

_M.FIELD_NAME_FILE = FIELD_NAME_FILE
_M.FIELD_NAME_CSRFTOKEN = FIELD_NAME_CSRFTOKEN

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
  }, _M)
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
        self.boundary = 'BNDR-' .. generate_random_hex_string(32)
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

_M.handle_form_field = function(self)
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

_M.get_upload_body_iterator = function(self, initial)
  local iterator = coroutine.wrap(self.upload_body_coro)
  -- pass function arguments in the first call (priming)
  iterator(self, initial)
  return iterator
end

_M.upload_body_coro = function(self, initial)
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
