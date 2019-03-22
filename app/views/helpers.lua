local config = require('config.app')


local link_url_prefix = config.link_url_prefix:match('(.-)/*$')


local _M = {}

_M.render_link_factory = function(tiny_id)
  local link_template = ('%s/%%s/%s'):format(link_url_prefix, tiny_id)
  return function(mode)
    return link_template:format(mode)
  end
end

return _M
