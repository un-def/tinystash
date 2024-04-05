local error = require('app.utils').error
local donate_config = require('app.config').donate


local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND

local enable_donate = donate_config.enable


return {

  initial = function()
    if not enable_donate then
      return error(ngx_HTTP_NOT_FOUND)
    end
  end,

  GET = {'web/donate.html', {
    intro = donate_config.intro,
    blocks = donate_config.blocks,
  }}

}
