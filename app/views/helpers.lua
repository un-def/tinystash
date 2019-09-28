local template = require('resty.template')

local config = require('app.config')


local ngx_print = ngx.print

local link_url_prefix = config.link_url_prefix:match('(.-)/*$')


local _M = {}

_M.render_link_factory = function(tiny_id)
  local link_template = ('%s/%%s/%s'):format(link_url_prefix, tiny_id)
  return function(mode)
    return link_template:format(mode)
  end
end

local render_to_string = function(template_path, context, plain)
  local full_context = {
    link_url_prefix = link_url_prefix,
  }
  if type(context) == 'table' then
    for k, v in pairs(context) do
      full_context[k] = v
    end
  end
  return template.compile(template_path, nil, plain)(full_context)
end

_M.render_to_string = render_to_string

_M.render = function(template_path, context, plain)
  ngx_print(render_to_string(template_path, context, plain))
end

return _M
