local json_encode = require('cjson.safe').encode

local tg = require('app.tg')
local utils = require('app.utils')

local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO

local prepare_connection = tg.prepare_connection
local request_tg_server = tg.request_tg_server
local get_file_from_message = tg.get_file_from_message

local guess_media_type = utils.guess_media_type
local log = utils.log


local mixin = {}

mixin.upload = function(self, url)
  -- params:
  --    url: string
  -- returns:
  --    if ok: TG API object (Document/Video/...) table with mandatory 'file_id' field
  --    if error: nil, error_code
  -- sets:
  --    self.conn: table -- http connection
  --    self.media_type: string
  --    self.bytes_uploaded: int
  local conn, res, err
  conn, err = prepare_connection()
  if not conn then
    log(ngx_ERR, 'tg api connection error: %s', err)
    return nil, ngx_HTTP_BAD_GATEWAY
  end
  self.conn = conn

  local body = json_encode{
    chat_id = self.chat_id,
    document = url,
  }
  local params = {
    path = '/bot%s/sendDocument',
    method = 'POST',
    headers = {
      ['content-type'] = 'application/json',
      ['content-length'] = #body,
    },
    body = body,
  }
  res, err = request_tg_server(conn, params, true)
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
  local _, media_type = guess_media_type(file_object, file.type)
  self:set_media_type(media_type)
  self.bytes_uploaded = file_object.file_size
  return file_object
end

return mixin
