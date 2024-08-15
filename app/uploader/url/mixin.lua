local tg = require('app.tg')
local utils = require('app.utils')

local tostring = tostring
local string_find = string.find
local string_lower = string.lower

local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO

local tg_client = tg.client
local get_file_from_message = tg.get_file_from_message

local guess_media_type = utils.guess_media_type
local log = utils.log


local _TG_ERR_PATTERN_FAILED = string_lower('failed to get HTTP URL content')
local _TG_ERR_PATTERN_REJECTED = string_lower('wrong file identifier/HTTP URL specified')

local _get_error_message_from_tg_error = function(err)
  local err_lower = string_lower(tostring(err))
  if string_find(err_lower, _TG_ERR_PATTERN_FAILED, 1, true) then
    return 'upstream failed to get URL content'
  end
  if string_find(err_lower, _TG_ERR_PATTERN_REJECTED, 1, true) then
    return 'upstream rejected to process URL'
  end
  return nil
end


local mixin = {}

mixin.upload = function(self, url)
  -- params:
  --    url: string
  -- returns:
  --    if ok: TG API object (Document/Video/...) table with mandatory 'file_id' field
  --    if error: nil, error_code, error_text?
  -- sets:
  --    self.client: tg.client
  --    self.media_type: string
  --    self.bytes_uploaded: int
  local client = tg_client()
  self.client = client
  local resp, err = client:send_document({
    chat_id = self.chat_id,
    document = url,
  })
  if err then
    log(ngx_ERR, 'tg api request error: %s', err)
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  if not resp.ok then
    local tg_err = resp.description
    log(ngx_INFO, 'tg api response is not "ok": %s', tg_err)
    return nil, ngx_HTTP_BAD_GATEWAY, _get_error_message_from_tg_error(tg_err)
  end
  if not resp.result then
    log(ngx_INFO, 'tg api response has no "result"')
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  local file
  file, err = get_file_from_message(resp.result)
  if not file then
    log(ngx_INFO, err)
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  local file_object = file.object
  if not file_object.file_id then
    log(ngx_INFO, 'tg api response has no "file_id"')
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  local _, media_type = guess_media_type(file_object, file.type)
  self:set_media_type(media_type)
  self.bytes_uploaded = file_object.file_size
  return file_object
end

return mixin
