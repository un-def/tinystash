local process_file = require('resty.template').new({
  root = TINYSTASH_DIR,
}).process_file

local config = require('app.config').nginx_conf
local CACHE_STATUS_HEADER = require('app.constants').CACHE_STATUS_HEADER


assert(OPENRESTY_PREFIX and OPENRESTY_PREFIX ~= '', 'OPENRESTY_PREFIX is not set')

local NUMBER = type(1)
local STRING = type('')
local BOOLEAN = type(true)
local TABLE = type({})

local NIL = {}

local option = function(params)
  local name = params[1]
  local value = config[name]
  if value == nil then
    if params.default == nil then
      error(("missing required option '%s'"):format(name))
    elseif params.default == NIL then
      value = nil
    else
      value = params.default
    end
  elseif params.validator then
    local err
    value, err = params.validator(value)
    if err then
      error(("option '%s' validation error: %s"):format(name, err))
    end
  end
  return value
end

local _type_validator = function(valid_types, value)
  local value_type = type(value)
  for _, valid_type in ipairs(valid_types) do
    if value_type == valid_type then
      return value
    end
  end
  return nil, ('invalid value type: expected %s, got %s'):format(
    table.concat(valid_types, ' or '), value_type)
end

local type_validator = function(...)
  local valid_types = {...}
  return function(value)
    return _type_validator(valid_types, value)
  end
end

local worker_processes_validator = function(value)
  if value == 'auto' or type(value) == NUMBER then
    return value
  end
  return nil, 'must be a number or "auto", got ' .. value
end

local lua_code_cache_validator = function(value)
  if value == 'on' or value == 'off' then
    return value
  elseif type(value) == BOOLEAN then
    return value and 'on' or 'off'
  end
  return nil, 'must be a boolean or "on" of "off", got ' .. value
end

local cache_status_header_validator = function(value)
  local err
  value, err = type_validator(BOOLEAN, STRING)(value)
  if err then
    return nil, err
  end
  if type(value) == STRING then
    if #value == 0 then
      return nil, 'empty string is not allowed'
    end
    return value
  end
  if value then
    return CACHE_STATUS_HEADER
  end
  return nil
end

local context = {
  worker_processes = option{'worker_processes', validator = worker_processes_validator, default = 'auto'},
  worker_connections = option{'worker_connections', validator = type_validator(NUMBER), default = NIL},
  error_log = option{'error_log', validator = type_validator(TABLE), default = {}},
  resolver = option{'resolver', validator = type_validator(STRING)},
  lua_ssl_trusted_certificate = option{'lua_ssl_trusted_certificate', validator = type_validator(STRING)},
  lua_ssl_verify_depth = option{'lua_ssl_verify_depth', validator = type_validator(NUMBER)},
  resty_http_debug_logging = option{'resty_http_debug_logging', validator = type_validator(BOOLEAN), default = false},
  listen = option{'listen', validator = type_validator(NUMBER)},
  access_log = option{'access_log', validator = type_validator(STRING), default = 'off'},
  lua_code_cache = option{'lua_code_cache', validator = lua_code_cache_validator, default = true},
  client_max_body_size = option{'client_max_body_size', validator = type_validator(STRING, NUMBER)},
  cache_valid = option{'cache_valid', validator = type_validator(STRING), default = NIL},
}

if context.cache_valid then
  context.cache_inactive = option{'cache_inactive', validator = type_validator(STRING), default = context.cache_valid}
  context.cache_zone_size = option{'cache_zone_size', validator = type_validator(STRING)}
  context.cache_max_size = option{'cache_max_size', validator = type_validator(STRING)}
  context.cache_status_header = option{'cache_status_header', validator = cache_status_header_validator, default = NIL}
end

print(process_file('nginx.conf.tpl', context))
