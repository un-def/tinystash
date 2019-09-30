local template = require('resty.template')

local config = require('app.config')


local ngx_print = ngx.print

local link_url_prefix = config._processed.link_url_prefix
local enable_upload = config._processed.enable_upload
local enable_upload_api = config._processed.enable_upload_api


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
    enable_upload = enable_upload,
    enable_upload_api = enable_upload_api,
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
