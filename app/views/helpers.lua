local template = require('resty.template')

local config = require('config.app')


local link_url_prefix = config.link_url_prefix:match('(.-)/*$')


local _M = {}

_M.render_link_factory = function(tiny_id)
  local link_template = ('%s/%%s/%s'):format(link_url_prefix, tiny_id)
  return function(mode)
    return link_template:format(mode)
  end
end

_M.render_to_string = function(template_path, context, plain)
  return template.compile(template_path, nil, plain)(context)
end

return _M
