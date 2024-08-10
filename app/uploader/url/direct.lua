local json_decode =require('cjson.safe').decode
local parse_header = require('httoolsp.headers').parse_header

local base = require('app.uploader.base')
local url_mixin = require('app.uploader.url.mixin')
local utils = require('app.utils')

local string_format = string.format
local ngx_ERR = ngx.ERR
local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_req = ngx.req
local ngx_var = ngx.var

local is_http_url = utils.is_http_url
local log = utils.log
local wrap_error = utils.wrap_error


local HTTP_UNSUPPORTED_MEDIA_TYPE = 415

local uploader = base.build_uploader(url_mixin, base.uploader)

uploader.new = function(_self, _upload_type, chat_id, _headers)
  local content_type = ngx_var.http_content_type
  if not content_type then
    log('no content-type')
    return nil, HTTP_UNSUPPORTED_MEDIA_TYPE
  end
  content_type = parse_header(content_type)
  local is_form = false
  local is_json = false
  local is_plain = false
  if content_type == 'application/x-www-form-urlencoded' then
    is_form = true
  elseif content_type == 'application/json' then
    is_json = true
  elseif content_type == 'text/plain' then
    is_plain = true
  else
    log('unsupported content type: %s', content_type)
    return nil, HTTP_UNSUPPORTED_MEDIA_TYPE
  end
  return setmetatable({
    chat_id = chat_id,
    is_form = is_form,
    is_json = is_json,
    is_plain = is_plain,
  }, uploader)
end

uploader.run = function(self)
  ngx_req.read_body()
  local url, err
  if self.is_form then
    url, err = self:parse_form()
  else
    local body = ngx_req.get_body_data()
    if not body then
      err = 'no body'
    elseif self.is_json then
      url, err = self:parse_json(body)
    elseif self.is_plain then
      url = body
    else
      log(ngx_ERR, 'should not reach here')
    end
  end
  if not url then
    log(err)
    return nil, ngx_HTTP_BAD_REQUEST
  end
  log('url: %s', url)
  if not is_http_url(url) then
    log('invalid url')
    return nil, ngx_HTTP_BAD_REQUEST
  end
  return self:upload(url)
end

uploader.parse_form = function(_self)
  local args, err = ngx_req.get_post_args()
  if err then
    return nil, err
  end
  local url = args.url
  if url == nil then
    return nil, 'no url field'
  end
  if type(url) == 'table' then
    return nil, 'multiple url fields'
  end
  return url
end

uploader.parse_json = function(_self, body)
  local json, err = json_decode(body)
  if not json then
    return nil, wrap_error('json decode error', err)
  end
  if type(json) ~= 'table' then
    return nil, string_format('json object expected, got: %s', type(json))
  end
  local url = json.url
  if url == nil then
    return nil, 'no url field'
  end
  if type(url) ~= 'string' then
    return nil, string_format('json string expected, got: %s', type(url))
  end
  return url
end

return uploader
