local upload = require('resty.upload')
local parse_header = require('httoolsp.headers').parse_header

local utils = require('app.utils')
local constants = require('app.constants')
local base = require('app.uploader.base')
local file_mixin = require('app.uploader.file.mixin')

local string_format = string.format
local ngx_null = ngx.null
local ngx_HTTP_FORBIDDEN = ngx.HTTP_FORBIDDEN
local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST

local log = utils.log
local wrap_error = utils.wrap_error

local CHUNK_SIZE = constants.CHUNK_SIZE
local CSRFTOKEN_FIELD_NAME = constants.CSRFTOKEN_FIELD_NAME


local uploader = base.build_uploader(file_mixin, base.form_mixin, base.uploader)

uploader.new = function(self, upload_type, chat_id, headers)
  local csrftoken, err = self:extract_csrftoken_from_cookies(headers)
  if not csrftoken then
    log(err)
    return nil, ngx_HTTP_BAD_REQUEST
  end
  local form
  form, err = upload:new(CHUNK_SIZE)
  if not form then
    log('resty.upload:new() error: %s', err)
    return nil, ngx_HTTP_BAD_REQUEST
  end
  form:set_timeout(1000) -- 1 sec
  return setmetatable({
    upload_type = upload_type,
    content_field = upload_type,
    chat_id = chat_id,
    csrftoken = csrftoken,
    form = form,
  }, uploader)
end

uploader.run = function(self)
  -- sets:
  --    self.media_type: string
  --    self.bytes_uploaded: int (via upload)
  --    self.client: tg.client (via upload)
  local csrftoken, file_object
  local ok, res, err, err_code
  while true do
    res, err = self:handle_form_field()
    if not res then
      log('handle_form_field() error: %s', err)
      return nil, ngx_HTTP_BAD_REQUEST
    elseif res == ngx_null then
      log('end of form')
      break
    else
      local field_name, filename, media_type, initial_data = unpack(res)
      if field_name == CSRFTOKEN_FIELD_NAME then
        csrftoken = initial_data
        ok, err = self:check_csrftoken(csrftoken)
        if not ok then
          log(err)
          return nil, ngx_HTTP_FORBIDDEN
        end
      elseif field_name == self.content_field then
        if initial_data:len() == 0 then
          return nil, ngx_HTTP_BAD_REQUEST, 'empty file'
        end
        self:set_media_type(media_type)
        self:set_filename(self.media_type, filename)
        local content_iterator = self:get_content_iterator(initial_data)
        file_object, err_code = self:upload(content_iterator)
        if not file_object then
          return nil, err_code
        end
      else
        log('unexpected form field: %s', filename)
        return nil, ngx_HTTP_BAD_REQUEST
      end
    end
  end
  ok, err = self:check_csrftoken(csrftoken)
  if not ok then
    log(err)
    return nil, ngx_HTTP_FORBIDDEN
  end
  if not file_object then
    log('no content')
    return nil, ngx_HTTP_BAD_REQUEST
  end
  return file_object
end

uploader.handle_form_field = function(self)
  -- returns:
  --    if eof: ngx.null
  --    if body (any): table {field_name, filename, media_type, initial_data}
  --    if error (any): nil, error_code, error_text?
  local form = self.form
  local field_name, filename, media_type
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
        local _, field = parse_header(value)
        field_name = field.name
        filename = field.filename
      end
    elseif token == 'body' and field_name then
      return {field_name, filename, media_type, data}
    end
  end
end

uploader.get_content_iterator = function(self, initial)
  local form = self.form
  local initial_sent = false
  local empty_chunk_seen = false
  local iterator
  iterator = function()
    if not initial_sent then
      initial_sent = true
      -- first chunk of the file
      return initial
    end
    local token, data, err = form:read()
    if not token then
      return nil, wrap_error('failed to read next form chunk', err)
    elseif token == 'body' then
      if #data == 0 then
        -- if file size % CHUNK_SIZE == 0, form:read() returns an empty string;
        -- we discard this chunk and expect 'part_end' token on the next iteration
        if empty_chunk_seen then
          return nil, 'two empty chunks in a row, part_end expected'
        end
        empty_chunk_seen = true
        return iterator()
      end
      empty_chunk_seen = false
      return data
    elseif token == 'part_end' then
      return nil
    else
      return nil, string_format('unexpected token: %s', token)
    end
  end
  return iterator
end

return uploader
