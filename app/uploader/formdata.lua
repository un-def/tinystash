local upload = require('resty.upload')

local utils = require('app.utils')
local constants = require('app.constants')
local base_uploader = require('app.uploader.base')


local ngx_null = ngx.null
local ngx_HTTP_FORBIDDEN = ngx.HTTP_FORBIDDEN
local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST

local log = utils.log
local format_error = utils.format_error

local CHUNK_SIZE = constants.CHUNK_SIZE


local FIELD_NAME_CONTENT = 'content'
local FIELD_NAME_CSRFTOKEN = 'csrftoken'


local get_form_field_name = function(content_disposition)
  return content_disposition:match('[ ;]name="([^"]+)"')
end


local _M = setmetatable({}, base_uploader)

_M.__index = _M

_M.FIELD_NAME_CONTENT = FIELD_NAME_CONTENT
_M.FIELD_NAME_CSRFTOKEN = FIELD_NAME_CSRFTOKEN

_M.new = function(_, upload_type, chat_id, headers)
  local cookie = headers['cookie']
  if not cookie then
    return nil, ngx_HTTP_BAD_REQUEST, 'no cookie header'
  end
  local csrftoken
  for key, value in cookie:gmatch('([^%c%s;]+)=([^%c%s;]+)') do
    if key == FIELD_NAME_CSRFTOKEN then
      csrftoken = value
      break
    end
  end
  if not csrftoken then
    return nil, ngx_HTTP_BAD_REQUEST, 'no csrftoken cookie'
  end
  local form, err = upload:new(CHUNK_SIZE)
  if not form then
    return nil, ngx_HTTP_BAD_REQUEST, err
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
  -- sets:
  --    self.media_type: string (via set_media_type)
  --    self.bytes_uploaded: int (via upload)
  --    self.boundary: string (via set_boundary)
  --    self.conn: http connection (via upload)
  local csrftoken, file_object
  local res, err, err_code
  while true do
    res, err = self:handle_form_field()
    if not res then
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
      elseif field_name == FIELD_NAME_CONTENT then
        if initial_data:len() == 0 then
          return nil, ngx_HTTP_BAD_REQUEST, 'empty file'
        end
        self:set_media_type(media_type)
        self:set_boundary()
        local content_iterator = self:get_content_iterator(initial_data)
        file_object, err_code, err = self:upload(content_iterator)
        if not file_object then
          return nil, err_code, err
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
  --    if eof: ngx.null
  --    if body (any): first chunk of body ("initial_data")
  --    if error (any): nil, error_code, error_text?
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

_M.get_content_iterator = function(self, initial)
  local form = self.form
  local initial_sent = false
  return function()
    if not initial_sent and initial then
      initial_sent = true
      -- first chunk of the file
      return initial
    end
    local token, data, err = form:read()
    if not token then
      return nil, format_error('failed to read next form chunk', err)
    elseif token == 'body' then
      return data
    elseif token == 'part_end' then
      return nil
    else
      return nil, format_error('unexpected token', token)
    end
  end
end


return _M
