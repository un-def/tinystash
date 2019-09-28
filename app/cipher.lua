local aes = require('resty.aes')

local aes_params = require('app.config').aes


local hash = aes_params.hash and aes.hash[aes_params.hash]
local cipher = aes.cipher(aes_params.size, aes_params.mode)
return aes:new(aes_params.key, aes_params.salt, cipher,
               hash, aes_params.hash_rounds)
