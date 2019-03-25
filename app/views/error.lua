local render_to_string = require('app.views.helpers').render_to_string


local REASONS = {
  [400] = 'Bad Request',
  [403] = 'Forbidden',
  [404] = 'Not Found',
  [405] = 'Method Not Allowed',
  [413] = 'Payload Too Large',
  [500] = 'Internal Server Error',
}


local error_page_cache = {}


local error_handler = function()
  local status_code = ngx.status
  local cached = error_page_cache[status_code]
  if cached then
    ngx.print(cached)
    return
  end
  local content = render_to_string('web/error.html', {
    title = status_code,
    status_code = status_code,
    reason = REASONS[status_code],
  })
  error_page_cache[status_code] = content
  ngx.print(content)
end


return {
  REASONS = REASONS,
  error_handler = error_handler,
}
