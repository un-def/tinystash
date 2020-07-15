local ffi = require('ffi')

local aes = require('resty.aes')
local aes_params = require('app.config').aes

local string_format = string.format

local ffi_new = ffi.new
local ffi_string = ffi.string
local C = ffi.C


ffi.cdef[[
  unsigned long ERR_get_error(void);
  void ERR_error_string_n(unsigned long e, char *buf, size_t len);
]]


local _M = {}

-- https://github.com/openresty/lua-resty-string/pull/65
local get_error = function(op)
    local errno = C.ERR_get_error()
    if errno == 0 then
        return nil
    end
    local msg = ffi_new('char[?]', 256)
    C.ERR_error_string_n(errno, msg, 256)
    return string_format('AES %s error: %s', op, ffi_string(msg))
end

local aes_obj = aes:new(
  aes_params.key,
  aes_params.salt,
  aes.cipher(aes_params.size, aes_params.mode),
  aes_params.hash and aes.hash[aes_params.hash],
  aes_params.hash_rounds
)

_M.encrypt = function(data)
  data = aes_obj:encrypt(data)
  if not data then
    return nil, get_error('encrypt')
  end
  return data
end

_M.decrypt = function(data)
  data = aes_obj:decrypt(data)
  if not data then
    return nil, get_error('decrypt')
  end
  return data
end

return _M
