local random_bytes = require('resty.random').bytes
local to_hex = require('resty.string').to_hex
local raw_log = require('ngx.errlog').raw_log

local constants = require('app.constants')
local mediatypes = require('app.mediatypes')


local debug_getinfo = debug.getinfo
local ngx_exec = ngx.exec
local ngx_DEBUG = ngx.DEBUG

local TG_TYPES_MEDIA_TYPES_MAP = constants.TG_TYPES_MEDIA_TYPES_MAP
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local TG_TYPE_STICKER = constants.TG_TYPES.STICKER
local DEFAULT_TYPE_ID = mediatypes.DEFAULT_TYPE_ID
local TYPE_ID_MAP = mediatypes.TYPE_ID_MAP
local ID_TYPE_MAP = mediatypes.ID_TYPE_MAP
local TYPE_EXT_MAP = mediatypes.TYPE_EXT_MAP


local LOG_LEVEL_NAMES = {
  [ngx.STDERR] = 'STDERR',
  [ngx.EMERG] = 'EMERG',
  [ngx.ALERT] = 'ALERT',
  [ngx.CRIT] = 'CRIT',
  [ngx.ERR] = 'ERR',
  [ngx.WARN] = 'WARN',
  [ngx.NOTICE] = 'NOTICE',
  [ngx.INFO] = 'INFO',
  [ngx_DEBUG] = 'DEBUG',
}


local _M = {}

_M.log = function(...)
  local level, message = ...
  local args_offset
  if type(level) ~= 'number' then
    message = level
    level = ngx_DEBUG
    args_offset = 2
  else
    args_offset = 3
  end
  if select('#', ...) - args_offset > -1 then
    message = tostring(message):format(select(args_offset, ...))
  end
  local info = debug_getinfo(2, 'Sln')
  message = ('%s:%s: %s():\n\n*** [%s] %s\n'):format(
    info.short_src:match('//(app/.+)'), info.currentline,
    info.name, LOG_LEVEL_NAMES[level], message)
  raw_log(level, message)
end

_M.error = function(status, description)
  return ngx_exec('/error', {status = status, description = description})
end

_M.format_error = function(preamble, error)
  if not error then
    return preamble
  end
  return ('%s: %s'):format(preamble, error)
end

_M.generate_random_hex_string = function(size)
  return to_hex(random_bytes(size))
end

_M.encode_urlsafe_base64 = function(to_encode)
  local encoded = ngx.encode_base64(to_encode, true)
  if not encoded then
    return nil, 'base64 encode error'
  end
  encoded = encoded:gsub('[%+/]', {['+'] = '-', ['/'] = '_' })
  return encoded
end

_M.decode_urlsafe_base64 = function(to_decode)
  to_decode = to_decode:gsub('[-_]', {['-'] = '+', ['_'] = '/' })
  local decoded = ngx.decode_base64(to_decode)
  if not decoded then
    return nil, 'base64 decode error'
  end
  return decoded
end

_M.escape_uri = function(uri, escape_slashes)
  if escape_slashes then return ngx.escape_uri(uri) end
  return uri:gsub('[^/]+', ngx.escape_uri)
end

local split_ext = function(path, exclude_dot)
  local root, ext = path:match('(.*[^/]+)%.([^./]+)$')
  root = root or path
  if ext and not exclude_dot then
    ext = '.' .. ext
  end
  return root, ext
end

_M.split_ext = split_ext

_M.escape_ext = function(filename)
  local root, ext = split_ext(filename)
  if not ext then
    ext = ''
  elseif ext:lower() == '.gif' then
    ext = '._if'
  end
  return root .. ext
end

_M.unescape_ext = function(filename)
  local root, ext = split_ext(filename)
  if not ext then
    ext = ''
  elseif ext == '._if' then
    ext = '.gif'
  end
  return root .. ext
end

_M.get_substring = function(str, start, length, blank_to_nil)
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

_M.parse_media_type = function(media_type)
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

_M.get_media_type_id = function(media_type)
  local media_type_id = TYPE_ID_MAP[media_type]
  if media_type_id then
    media_type = ID_TYPE_MAP[media_type_id]
  end
  return media_type_id, media_type
end

_M.normalize_media_type = function(media_type)
  local media_type_table
  if type(media_type) == 'table' then
    media_type_table = media_type
  else
    media_type_table = _M.parse_media_type(media_type)
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

_M.guess_media_type = function(file_obj, file_obj_type)
  local media_type, media_type_id
  media_type = file_obj.mime_type and file_obj.mime_type:lower()
  -- guess by tg object 'mime_type' property
  if media_type then
    -- try unprocessed 'mime_type'
    media_type_id, media_type = _M.get_media_type_id(media_type)
    if media_type_id then
      return media_type_id, media_type
    end
    -- try normalized 'mime_type'
    local media_type_table = _M.parse_media_type(media_type)
    if media_type_table then
      media_type = _M.normalize_media_type(media_type_table)
      media_type_id, media_type = _M.get_media_type_id(media_type)
      if media_type_id then
        return media_type_id, media_type
      end
      -- fallback unknown 'text/{subtype}' to 'text/plain'
      if media_type_table[1] == 'text' then
        return _M.get_media_type_id('text/plain')
      end
    end
    return DEFAULT_TYPE_ID, nil
  end
  if file_obj_type == TG_TYPE_STICKER then
    -- special case for stickers
    if file_obj.is_animated then
      -- tgs -> fallback to default media type, i.e., 'application/octet-stream'
      media_type = nil
    else
      media_type = 'image/webp'
    end
  else
    -- otherwise guess by tg object type
    media_type = TG_TYPES_MEDIA_TYPES_MAP[file_obj_type]
  end
  if media_type then
    return _M.get_media_type_id(media_type)
  end
  return DEFAULT_TYPE_ID, nil
end

_M.guess_extension = function(params)
  -- params combinations:
  --   * file_obj AND file_obj_type
  --   * file_name
  --   * nothing
  -- optional params: media_type, exclude_dot
  local ext, file_name, _
  if params.file_obj then
    file_name = params.file_obj.file_name
  else
    file_name = params.file_name
  end
  if file_name then
    _, ext = _M.split_ext(file_name, true)
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

return _M
