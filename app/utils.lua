local constants = require('app.constants')
local mediatypes = require('app.mediatypes')

local TG_TYPES_MEDIA_TYPES_MAP = constants.TG_TYPES_MEDIA_TYPES_MAP
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local DEFAULT_TYPE_ID = mediatypes.DEFAULT_TYPE_ID
local TYPE_ID_MAP = mediatypes.TYPE_ID_MAP
local ID_TYPE_MAP = mediatypes.ID_TYPE_MAP
local TYPE_EXT_MAP = mediatypes.TYPE_EXT_MAP


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

M.parse_media_type = function(media_type)
  local type_, subtype, suffix = media_type:match(
    '^([%w_-]+)/([.%w_-]+)%+?([%w_-]-)$')
  if not type_ then
    return nil, 'Media type parse error'
  end
  if suffix == '' then
    suffix = nil
  end
  local x = false
  if subtype:sub(1, 2) == 'x-' then
    subtype = subtype:sub(3)
    x = true
  end
  return {type_, subtype, suffix, x}
end

M.normalize_media_type = function(media_type)
  local media_type_table
  if type(media_type) == 'table' then
    media_type_table = media_type
  else
    media_type_table = M.parse_media_type(media_type)
    if not media_type_table then return media_type end
  end
  local type_, subtype, suffix = unpack(media_type_table)
  -- normalize {type}/{subtype}+xml, e.g., text/html+xml
  if suffix == 'xml' then
    if subtype == 'html' then
      return type_ .. '/html'
    else
      return type_ .. '/xml'
    end
  end
  -- remove 'x-' subtype prefix
  return ('%s/%s%s'):format(type_, subtype, suffix and '+' .. suffix or '')
end

local _get_media_type_id = function(media_type)
  local media_type_id = TYPE_ID_MAP[media_type]
  if media_type_id then
    media_type = ID_TYPE_MAP[media_type_id]
  end
  return media_type_id, media_type
end

M.guess_media_type = function(file_obj, file_obj_type)
  local media_type, media_type_id
  media_type = file_obj.mime_type and file_obj.mime_type:lower()
  -- guess by tg object 'mime_type' property
  if media_type then
    -- try unprocessed 'mime_type'
    media_type_id, media_type = _get_media_type_id(media_type)
    if media_type_id then
      return media_type_id, media_type
    end
    -- try normalized 'mime_type'
    local media_type_table = M.parse_media_type(media_type)
    if media_type_table then
      media_type = M.normalize_media_type(media_type_table)
      media_type_id, media_type = _get_media_type_id(media_type)
      if media_type_id then
        return media_type_id, media_type
      end
      -- fallback unknown 'text/{subtype}' to 'text/plain'
      if media_type_table[1] == 'text' then
        return _get_media_type_id('text/plain')
      end
    end
    return DEFAULT_TYPE_ID, nil
  end
  -- guess by tg object type
  media_type = TG_TYPES_MEDIA_TYPES_MAP[file_obj_type]
  if media_type then
    return _get_media_type_id(media_type)
  end
  return DEFAULT_TYPE_ID, nil
end

M.guess_extension = function(params)
  -- required params: file_obj AND file_obj_type OR file_name
  -- optional params: media_type, exclude_dot
  local ext, file_name, _
  if params.file_obj then
    file_name = params.file_obj.file_name
  else
    file_name = params.file_name
  end
  if file_name then
    _, ext = M.split_ext(file_name, true)
  end
  if not ext and params.file_obj_type then
    ext = TG_TYPES_EXTENSIONS_MAP[params.file_obj_type]
  end
  if not ext and params.media_type then
    ext = TYPE_EXT_MAP[params.media_type]
  end
  if ext and not params.exclude_dot then
    return '.' .. ext
  end
  return ext
end

return M
