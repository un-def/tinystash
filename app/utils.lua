local random_bytes = require('resty.random').bytes
local to_hex = require('resty.string').to_hex
local raw_log = require('ngx.errlog').raw_log

local constants = require('app.constants')
local mediatypes = require('app.mediatypes')


local string_match = string.match
local string_byte = string.byte
local string_sub = string.sub
local string_format = string.format
local debug_getinfo = debug.getinfo
local ngx_exec = ngx.exec
local ngx_DEBUG = ngx.DEBUG

local TG_TYPES_MEDIA_TYPES_MAP = constants.TG_TYPES_MEDIA_TYPES_MAP
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local TG_TYPE_STICKER = constants.TG_TYPES.STICKER
local DEFAULT_TYPE_ID = mediatypes.DEFAULT_TYPE_ID
local DEFAULT_TYPE = mediatypes.DEFAULT_TYPE
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

local _error_mt = {
  __tostring = function(self)
    local error = self._error
    if error == nil then
      return self._prefix
    end
    return string_format('%s: %s', self._prefix, error)
  end,
}

_M.wrap_error = function(prefix, error)
  local error_t = {
    _prefix = prefix,
    _error = error,
  }
  return setmetatable(error_t, _error_mt)
end

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
  if select('#', ...) >= args_offset then
    message = string_format(message, select(args_offset, ...))
  end
  local info = debug_getinfo(2, 'Sln')
  message = ('%s:%s: %s:\n\n*** [%s] %s\n'):format(
    info.short_src:match('//(app/.+)'), info.currentline,
    info.name, LOG_LEVEL_NAMES[level], message)
  raw_log(level, message)
end

_M.error = function(status, description)
  return ngx_exec('/error', {status = status, description = description})
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

_M.is_http_url = function(str)
  return string_match(str, '^https?://.+') ~= nil
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

local parse_media_type = function(media_type)
  local type_, subtype, suffix = media_type:match(
    '^([%w_-]+)/([.%w_-]+)%+?([%w_-]-)$')
  if not type_ then
    return nil, 'Media type parse error'
  end
  local has_x = subtype:sub(1, 2) == 'x-'
  -- [1] -- string, type, non-empty
  -- [2] -- string, subtype including tree and x- prefix (if any)
  -- [3] -- string, suffix excluding plus sign, may be empty
  -- [4] -- boolean, true if subtype has x- prefix
  return {type_, subtype, suffix, has_x}
end

_M.parse_media_type = parse_media_type

local _render_media_type = function(type_, subtype, suffix)
  if suffix and suffix ~= '' then
    return ('%s/%s+%s'):format(type_, subtype, suffix)
  end
  return ('%s/%s'):format(type_, subtype)
end

local render_media_type = function(media_type_table, with_x)
  -- with_x: boolean -- force adding or removing x- prefix
  -- if with_x is not set (nil), keep x- prefix as is
  local type_, subtype, suffix, has_x = unpack(media_type_table)
  if with_x ~= nil then
    if with_x and not has_x then
      subtype = 'x-' .. subtype
    end
    if not with_x and has_x then
      subtype = subtype:sub(3)
    end
  end
  return _render_media_type(type_, subtype, suffix)
end

_M.render_media_type = render_media_type

local _get_media_type_id = function(media_type)
  if media_type == DEFAULT_TYPE then
    return DEFAULT_TYPE_ID, DEFAULT_TYPE
  end
  local media_type_id = TYPE_ID_MAP[media_type]
  if media_type_id then
    return media_type_id, ID_TYPE_MAP[media_type_id]
  end
  return nil, media_type
end

local get_media_type_id = function(media_type)
  -- NB: media_type is modified across this function
  local media_type_id

  -- first, try media_type as is
  media_type_id, media_type = _get_media_type_id(media_type)
  if media_type_id then
    return media_type_id, media_type
  end

  local media_type_table = parse_media_type(media_type)
  if not media_type_table then
    return DEFAULT_TYPE_ID, DEFAULT_TYPE
  end
  local type_, subtype, suffix, has_x = unpack(media_type_table)

  -- try with x- prefix added/removed
  media_type = render_media_type(media_type_table, not has_x)
  media_type_id, media_type = _get_media_type_id(media_type)
  if media_type_id then
    return media_type_id, media_type
  end

  -- try with {type}/{subtype}+xml (e.g., text/html+xml) normalized
  if suffix == 'xml' then
    if subtype == 'html' then
      media_type = _render_media_type(type_, 'html')
    else
      media_type = _render_media_type(type_, 'xml')
    end
    media_type_id, media_type = _get_media_type_id(media_type)
    if media_type_id then
      return media_type_id, media_type
    end
  end

  -- fallback unknown 'text/{subtype}' to 'text/plain'
  if type_ == 'text' then
    return _get_media_type_id('text/plain')
  end

  return DEFAULT_TYPE_ID, DEFAULT_TYPE
end

_M.get_media_type_id = get_media_type_id

_M.guess_media_type = function(file_obj, file_obj_type)
  local media_type = file_obj.mime_type and file_obj.mime_type:lower()
  -- guess by tg object 'mime_type' property
  if media_type then
    return get_media_type_id(media_type)
  end
  if file_obj_type == TG_TYPE_STICKER then
    -- special case for stickers
    if file_obj.is_animated then
      -- tgs -> fallback to default media type, i.e., 'application/octet-stream'
      media_type = DEFAULT_TYPE
    else
      media_type = 'image/webp'
    end
  else
    -- otherwise guess by tg object type
    media_type = TG_TYPES_MEDIA_TYPES_MAP[file_obj_type]
  end
  if media_type then
    return get_media_type_id(media_type)
  end
  return DEFAULT_TYPE_ID, DEFAULT_TYPE
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

_M.format_file_size = function(size)
  if size == 1 then
    return '1 byte'
  end
  local byte_size = ('%d bytes'):format(size)
  if size < 1024 then
    return byte_size
  end
  local unit
  local unit_size
  if size < 1048576 then
    unit = 'kiB'
    unit_size = size / 1024
  else
    unit = 'MiB'
    unit_size = size / 1048576
  end
  return ('%.1f %s (%s)'):format(unit_size, unit, byte_size)
end

_M.set = function(item_t)
  local set_t = {}
  for _, item in ipairs(item_t) do
    set_t[item] = true
  end
  return set_t
end

local _utf8_next = function(str, at)
  -- returns next code point byte index, current code point width
  if at > #str then
    return nil
  end
  local width
  local byte = string_byte(str, at)
  if byte < 192 then
    width = 1
  elseif byte < 224 then
    width = 2
  elseif byte < 240 then
    width = 3
  else
    width = 4
  end
  return at + width, width
end

local _utf8_scan = function(str)
  -- iterator, string, position
  return _utf8_next, str, 1
end

_M.utf8_sub = function(str, from, to)
  if not from or from < 1 then error('from must be positive') end
  if to and to < 1 then error('to must be positive') end
  if to < from then error('to must be >= from') end
  local cur = 1   -- current code point index
  local from_byte
  for next_byte, width in _utf8_scan(str) do
    if cur == from then
      from_byte = next_byte - width
      if not to then
        return string_sub(str, from_byte)
      end
    end
    if cur == to then
      return string_sub(str, from_byte, next_byte - 1)
    end
    cur = cur + 1
  end
end

return _M
