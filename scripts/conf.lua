local compile_template = require('resty.template').compile

local config = require('app.config').nginx_conf

local NUMBER = type(1)
local STRING = type('')
local BOOLEAN = type(true)
local TABLE = type({})

local option = function(params)
  local name = params[1]
  local value = config[name]
  if value == nil then
    if params.required then
      error(("missing required option '%s'"):format(name))
    elseif params.default ~= nil then
      value = params.default
    end
  elseif params.type then
    local type = type(value)
    if type ~= params.type then
      error(("option '%s' has invalid value type: expected %s, got %s"):format(
        name, params.type, type))
    end
  end
  return value
end

local fd = assert(io.open(_G.TINYSTASH_DIR .. '/nginx.conf.tpl', 'r'))
local template = assert(fd:read('*a'))
fd:close()

local context = {
  worker_processes = option{'worker_processes', type = NUMBER, required = true},
  worker_connections = option{'worker_connections', type = NUMBER, required = true},
  error_log = option{'error_log', type = TABLE, default = {}},
  resolver = option{'resolver', type = STRING, required = true},
  lua_ssl_trusted_certificate = option{'lua_ssl_trusted_certificate', type = STRING, required = true},
  lua_ssl_verify_depth = option{'lua_ssl_verify_depth', type = NUMBER, required = true},
  resty_http_debug_logging = option{'resty_http_debug_logging', type = BOOLEAN, default = false},
  listen = option{'listen', type = NUMBER, required = true},
  access_log = option{'access_log', type = STRING, default = 'off'},
  lua_code_cache = option{'lua_code_cache', type = STRING, default = 'on'},
  client_max_body_size = option{'client_max_body_size', required = true},
}
print(compile_template(template, nil, true)(context))
