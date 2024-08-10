local base = require('app.uploader.base')
local url_mixin = require('app.uploader.url.mixin')


local uploader = base.build_uploader(url_mixin, base.uploader)

return uploader
