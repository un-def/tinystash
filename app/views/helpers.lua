local process_file = require('resty.template').new({
  root = 'templates',
}).process_file

local config = require('app.config')


local ngx_print = ngx.print

local link_url_prefix = config._processed.link_url_prefix
local url_path_prefix = config._processed.url_path_prefix
local enable_upload = config._processed.enable_upload
local enable_upload_api = config._processed.enable_upload_api
local enable_donate = config.donate.enable
local gtm_id = config.gtm_id


local _M = {}

_M.render_link_factory = function(tiny_id)
  local link_template = ('%s/%%s/%s'):format(link_url_prefix, tiny_id)
  return function(mode)
    return link_template:format(mode)
  end
end

local render_to_string = function(template_path, context)
  local full_context = {
    link_url_prefix = link_url_prefix,
    url_path_prefix = url_path_prefix,
    enable_upload = enable_upload,
    enable_upload_api = enable_upload_api,
    enable_donate = enable_donate,
    gtm_id = gtm_id,
  }
  if type(context) == 'table' then
    for k, v in pairs(context) do
      full_context[k] = v
    end
  end
  return process_file(template_path, full_context)
end

_M.render_to_string = render_to_string

_M.render = function(template_path, context)
  ngx_print(render_to_string(template_path, context))
end

local markdown_escape_cb = function(char)
  return ([[\%s]]):format(char)
end

_M.markdown_escape = function(text)
  return text:gsub('[_*`[]', markdown_escape_cb)
end

return _M
