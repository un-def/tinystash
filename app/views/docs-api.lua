local error = require('app.utils').error
local enable_upload_api = require('app.config')._processed.enable_upload_api


local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND


return {

  initial = function()
    if not enable_upload_api then
      return error(ngx_HTTP_NOT_FOUND)
    end
  end,

  GET = 'web/docs-api.html',

}
