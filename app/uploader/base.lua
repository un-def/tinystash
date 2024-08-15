local utils = require('app.utils')
local constants = require('app.constants')
local DEFAULT_TYPE = require('app.mediatypes').DEFAULT_TYPE


local CSRFTOKEN_FIELD_NAME = constants.CSRFTOKEN_FIELD_NAME

local log = utils.log
local guess_extension = utils.guess_extension
local escape_ext = utils.escape_ext
local generate_random_hex_string = utils.generate_random_hex_string


local not_implemented = function()
  error('not implemented')
end


local uploader = {}

uploader.MAX_FILE_SIZE = constants.TG_MAX_FILE_SIZE

uploader.new = function()
  -- params:
  --    upload_type: string -- 'file' | 'text' | 'url'
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

uploader.run = function()
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

uploader.close = function(self)
  local client = self.client
  if client then
    client:close()
    self.client = nil
  end
end

uploader.is_max_file_size_exceeded = function(self, file_size)
  return file_size > self.MAX_FILE_SIZE
end

uploader.set_media_type = function(self, media_type)
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

uploader.set_filename = function(self, media_type, filename)
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

local form_mixin = {}

form_mixin.extract_csrftoken_from_cookies = function(_, headers)
  local cookie = headers['cookie']
  if not cookie then
    return nil, 'no cookie header'
  end
  for key, value in cookie:gmatch('([^%c%s;]+)=([^%c%s;]+)') do
    if key == CSRFTOKEN_FIELD_NAME then
      return value
    end
  end
  return nil, 'no csrftoken cookie'
end

form_mixin.check_csrftoken = function(self, csrftoken, expected)
  if expected == nil then
    expected = self.csrftoken
  end
  if csrftoken == nil then
    return false, 'no csrf token'
  elseif type(csrftoken) == 'table' then
    return false, 'multiple csrf token fields'
  elseif csrftoken ~= expected then
    return false, 'invalid csrf token'
  end
  return true
end

local build_uploader = function(...)
  local bases = {...}
  local uploader_mt = {}
  uploader_mt.__index = uploader_mt
  for idx = #bases, 1, -1 do
    for key, value in pairs(bases[idx]) do
      uploader_mt[key] = value
    end
  end
  return uploader_mt
end

return {
  build_uploader = build_uploader,
  form_mixin = form_mixin,
  uploader = uploader,
}
