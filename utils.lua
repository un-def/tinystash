local M = {}

M.log = function(...)
  local level, message = ...
  local args_offset
  if type(level) ~= 'number' then
    message = level
    level = ngx.DEBUG
    args_offset = 2
  else
    args_offset = 3
  end
  message = tostring(message)
  ngx.log(level, '\n\n*** ', message:format(select(args_offset, ...)), '\n')
end

M.encode_urlsafe_base64 = function(to_encode)
  local encoded = ngx.encode_base64(to_encode, true)
  if not encoded then
    return nil, 'base64 encode error'
  end
  encoded = encoded:gsub('[%+/]', {['+'] = '-', ['/'] = '_' })
  return encoded
end

M.decode_urlsafe_base64 = function(to_decode)
  to_decode = to_decode:gsub('[-_]', {['-'] = '+', ['_'] = '/' })
  local decoded = ngx.decode_base64(to_decode)
  if not decoded then
    return nil, 'base64 decode error'
  end
  return decoded
end

return M
