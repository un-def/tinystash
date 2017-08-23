local mediatypes = require('app.mediatypes')
local constants = require('app.constants')

local TG_TYPES_MEDIA_TYPES_MAP = constants.TG_TYPES_MEDIA_TYPES_MAP
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP


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

M.exit = function(status, content)
  if not content then ngx.exit(status) end
  ngx.status = status
  ngx.header['Content-Type'] = 'text/plain'
  ngx.print(content)
  ngx.exit(ngx.HTTP_OK)
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

M.escape_uri = function(uri, escape_slashes)
  if escape_slashes then return ngx.escape_uri(uri) end
  return uri:gsub('[^/]+', ngx.escape_uri)
end

M.get_basename = function(path)
  return path:match('/([^/]*)$') or path
end

M.split_ext = function(path, exclude_dot)
  local root, ext = path:match('(.*[^/]+)%.([^./]+)$')
  root = root or path
  if ext and not exclude_dot then
    ext = '.' .. ext
  end
  return root, ext
end

M.get_substring = function(str, start, length, blank_to_nil)
  local stop, next
  if not length then
    stop = #str
  else
    stop = start + length - 1
    if stop < #str then next = stop + 1 end
  end
  local substr = str:sub(start, stop)
  if blank_to_nil and #substr == 0 then substr = nil end
  return substr, next
end

M.guess_media_type = function(file_obj, file_obj_type)
  return file_obj.mime_type or TG_TYPES_MEDIA_TYPES_MAP[file_obj_type]
end


M.guess_extension = function(file_obj, file_obj_type, media_type,
                                 exclude_dot)
  local ext, _
  if file_obj.file_name then
    _, ext = M.split_ext(file_obj.file_name, true)
  end
  if not ext then
    ext = TG_TYPES_EXTENSIONS_MAP[file_obj_type]
  end
  if not ext and media_type then
    ext = mediatypes.TYPE_EXT_MAP[media_type]
  end
  if ext and not exclude_dot then
    return '.' .. ext
  end
  return ext
end

return M
