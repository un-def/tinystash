local base58 = require('basex').base58bitcoin

local cipher = require('cipher')
local utils = require('utils')


local M = {}

M.encode = function(tiny_id_data)
  local file_id_bytes, err = utils.decode_urlsafe_base64(tiny_id_data.file_id)
  if not file_id_bytes then
    return nil, err
  end
  local tiny_id_src = string.char(#file_id_bytes) .. file_id_bytes
  local tiny_id_bytes = cipher:encrypt(tiny_id_src)
  return base58:encode(tiny_id_bytes)
end

M.decode = function(tiny_id)
  local tiny_id_bytes, err = base58:decode(tiny_id)
  if not tiny_id_bytes then
    return nil, err
  end
  local tiny_id_src = cipher:decrypt(tiny_id_bytes)
  if not tiny_id_src then
    return nil, 'AES decrypt error'
  end
  local file_id_size = string.byte(tiny_id_src:sub(1, 1))
  if not file_id_size or file_id_size < 1 then
    return nil, 'Wrong file_id size'
  end
  local file_id_bytes = tiny_id_src:sub(2, file_id_size+1)
  if #file_id_bytes < file_id_size then
    return nil, 'file_id size less than declared'
  end
  local tiny_id_data = {
    file_id = utils.encode_urlsafe_base64(file_id_bytes)
  }
  return tiny_id_data
end

return M
