local base58 = require('basex').base58bitcoin

local cipher = require('app.cipher')
local mediatypes = require('app.mediatypes')
local utils = require('app.utils')

local decode_urlsafe_base64 = utils.decode_urlsafe_base64
local encode_urlsafe_base64 = utils.encode_urlsafe_base64
local get_substring = utils.get_substring


local M = {}

M.encode = function(params)
  local file_id_bytes, err = decode_urlsafe_base64(params.file_id)
  if not file_id_bytes then
    return nil, err
  end
  local file_id_size_byte = string.char(#file_id_bytes)
  local media_type_id = mediatypes.TYPE_ID_MAP[params.media_type] or 0
  local media_type_byte = string.char(media_type_id)
  local tiny_id_raw_bytes = table.concat{
    file_id_size_byte,
    file_id_bytes,
    media_type_byte,
  }
  local tiny_id_encr_bytes = cipher:encrypt(tiny_id_raw_bytes)
  return base58:encode(tiny_id_encr_bytes)
end

M.decode = function(tiny_id)
  -- decrypt tiny_id
  local tiny_id_encr_bytes, err = base58:decode(tiny_id)
  if not tiny_id_encr_bytes then
    return nil, err
  end
  local tiny_id_raw_bytes = cipher:decrypt(tiny_id_encr_bytes)
  if not tiny_id_raw_bytes then
    return nil, 'AES decrypt error'
  end
  -- get file_id size
  local file_id_size = string.byte(tiny_id_raw_bytes:sub(1, 1))
  if not file_id_size or file_id_size < 1 then
    return nil, 'Wrong file_id size'
  end
  -- get file_id
  local file_id_bytes, pos
  file_id_bytes, pos = get_substring(tiny_id_raw_bytes, 2, file_id_size)
  if #file_id_bytes < file_id_size then
    return nil, 'file_id size less than declared'
  end
  local file_id = encode_urlsafe_base64(file_id_bytes)
  -- get media_type
  local media_type = nil
  if pos then
    local media_type_byte = get_substring(tiny_id_raw_bytes, pos, 1)
    local media_type_id = string.byte(media_type_byte)
    if media_type_id ~= 0 then
      media_type = mediatypes.ID_TYPE_MAP[media_type_id]
    end
  end

  return {
    file_id = file_id,
    media_type = media_type,
  }
end

return M
