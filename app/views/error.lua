local json_encode = require('cjson.safe').encode
local parse_accept_header = require('httoolsp.headers').parse_accept_header

local render_to_string = require('app.views.helpers').render_to_string


local ngx_say = ngx.say
local ngx_exit = ngx.exit
local ngx_req = ngx.req
local ngx_header = ngx.header
local ngx_HTTP_OK = ngx.HTTP_OK


local REASONS = {
  [400] = 'Bad Request',
  [403] = 'Forbidden',
  [404] = 'Not Found',
  [405] = 'Method Not Allowed',
  [413] = 'Payload Too Large',
  [411] = 'Length Required',
  [500] = 'Internal Server Error',
  [501] = 'Not Implemented',
  [502] = 'Bad Gateway',
}


local MEDIA_TYPES = {
  'text/html',
  'application/json',
  'text/plain',
}

local DEFAULT_MEDIA_TYPE = MEDIA_TYPES[1]


local error_page_cache = {}


local error_handler = function()
  local args = ngx_req.get_uri_args()
  local status = tonumber(args.status or ngx.status)
  ngx.status = status
  local description = args.description

  local content_type
  local accept_header = ngx_req.get_headers()['accept']
  if type(accept_header) == 'table' then
    accept_header = accept_header[1]
  end
  if accept_header then
    content_type = parse_accept_header(accept_header):negotiate(MEDIA_TYPES)
  end
  if not content_type then
    content_type = DEFAULT_MEDIA_TYPE
  end
  ngx_header['content-type'] = content_type

  if content_type == 'text/plain' then
    ngx_say('ERROR: ', description or status)
    return ngx_exit(ngx_HTTP_OK)
  elseif content_type == 'application/json' then
    ngx_say(json_encode{
      error_code = status,
      error_description = description,
    })
    return ngx_exit(ngx_HTTP_OK)
  else
    -- do not cache error pages with arbitrary descriptions
    local cacheable = not description
    if cacheable then
      local cached = error_page_cache[status]
      if cached then
        ngx_say(cached)
        return ngx_exit(ngx_HTTP_OK)
      end
    end
    local content = render_to_string('web/error.html', {
      title = status,
      status = status,
      reason = REASONS[status],
      description = description,
    })
    if cacheable then
      error_page_cache[status] = content
    end
    ngx_say(content)
    return ngx_exit(ngx_HTTP_OK)
  end
end


return {
  REASONS = REASONS,
  error_handler = error_handler,
}
