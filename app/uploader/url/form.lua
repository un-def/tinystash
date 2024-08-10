local utils = require('app.utils')
local base = require('app.uploader.base')
local url_mixin = require('app.uploader.url.mixin')

local ngx_HTTP_FORBIDDEN = ngx.HTTP_FORBIDDEN
local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_req = ngx.req

local log = utils.log
local is_http_url = utils.is_http_url


local uploader = base.build_uploader(url_mixin, base.form_mixin, base.uploader)

uploader.new = function(self, _upload_type, chat_id, headers)
  local csrftoken, err = self:extract_csrftoken_from_cookies(headers)
  if not csrftoken then
    log(err)
    return nil, ngx_HTTP_BAD_REQUEST
  end
  return setmetatable({
    chat_id = chat_id,
    csrftoken = csrftoken,
  }, uploader)
end

uploader.run = function(self)
  -- sets:
  --    self.media_type: string
  --    self.bytes_uploaded: int (via upload)
  --    self.conn: http connection (via upload)
  ngx_req.read_body()
  local args, err = ngx_req.get_post_args()
  if err then
    log(err)
    return nil, ngx_HTTP_BAD_REQUEST
  end
  local ok
  ok, err = self:check_csrftoken(args.csrftoken)
  if not ok then
    log(err)
    return nil, ngx_HTTP_FORBIDDEN
  end
  local url = args.url
  log('url: %s', url)
  if url == nil then
    log('no url')
    return nil, ngx_HTTP_BAD_REQUEST
  elseif type(url) == 'table' then
    log('multiple url fields')
    return nil, ngx_HTTP_BAD_REQUEST
  elseif not is_http_url(url) then
    log('invalid url')
    return nil, ngx_HTTP_BAD_REQUEST, 'invalid URL'
  end
  local file_object, err_code = self:upload(url)
  if not file_object then
    return nil, err_code
  end
  return file_object
end

return uploader
