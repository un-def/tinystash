local tg = require('app.tg')
local utils = require('app.utils')

local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO

local URL_UPLOAD_ERROR_FAILED = tg.URL_UPLOAD_ERROR_FAILED
local URL_UPLOAD_ERROR_REJECTED = tg.URL_UPLOAD_ERROR_REJECTED
local tg_client = tg.client
local get_file_from_message = tg.get_file_from_message
local get_url_upload_error_type = tg.get_url_upload_error_type

local guess_media_type = utils.guess_media_type
local log = utils.log


local _get_error_message_from_tg_error = function(err)
  local err_type = get_url_upload_error_type(err)
  if err_type == URL_UPLOAD_ERROR_FAILED then
    return 'upstream failed to get URL content'
  end
  if err_type == URL_UPLOAD_ERROR_REJECTED then
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
