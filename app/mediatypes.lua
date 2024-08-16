local DEFAULT_TYPE_ID = 0
local DEFAULT_TYPE = 'application/octet-stream'

-- KEEP THIS ARRAY DENSE!
-- format: [media type id] = {'correct media type', ...aliases..., extension}
-- specify media types without 'x-', e.g., 'text/lua' instead of 'text/x-lua'
local MEDIA_TYPES = {
  -- audio types
  [1] = {'audio/mpeg', 'audio/mp3', 'mp3'},
  [2] = {'audio/mp4', 'm4a'},
  [3] = {'audio/flac', 'flac'},
  [4] = {'audio/ogg', 'audio/vorbis+ogg', 'audio/opus+ogg',
         'audio/flac+ogg', 'audio/speex+ogg', 'audio/speex', 'ogg'},
  -- image types
  [5] = {'image/jpeg', 'jpg'},
  [6] = {'image/png', 'png'},
  [7] = {'image/bmp', 'bmp'},
  [8] = {'image/gif', 'gif'},
  [16] = {'image/webp', 'webp'},
  [19] = {'image/svg+xml', 'svg'},
  [24] = {'image/jxl', 'jxl'},
  [25] = {'image/jxr', 'jxr'},
  -- application types
  [9] = {'application/pdf', 'pdf'},
  [10] = {'application/xml', 'xml'},
  [14] = {'application/javascript', 'js'},
  [15] = {'application/json', 'json'},
  [20] = {'application/zip', 'zip'},
  [21] = {'application/gzip', 'gz'},
  -- text types
  [11] = {'text/plain', 'txt'},
  [12] = {'text/html', 'html'},
  [13] = {'text/xml', 'xml'},
  -- video types
  [17] = {'video/mp4', 'mp4'},
  [18] = {'video/webm', 'webm'},
  [22] = {'video/matroska', 'mkv'},
  [23] = {'video/quicktime', 'mov'},

  -- [26] = {},   -- next index
}


local ID_TYPE_MAP = {}
local TYPE_ID_MAP = {}
local TYPE_EXT_MAP = {}


for media_type_id = 1, #MEDIA_TYPES do
  local media_type_table = MEDIA_TYPES[media_type_id]
  local media_type_table_size = #media_type_table
  local media_type = media_type_table[1]
  local extension = media_type_table[media_type_table_size]
  TYPE_ID_MAP[media_type] = media_type_id
  ID_TYPE_MAP[media_type_id] = media_type
  TYPE_EXT_MAP[media_type] = extension
  if media_type_table_size > 2 then
    for index = 2, media_type_table_size-1 do
      local media_type_alias = media_type_table[index]
      TYPE_ID_MAP[media_type_alias] = media_type_id
      TYPE_EXT_MAP[media_type_alias] = extension
    end
  end
end


return {
  DEFAULT_TYPE_ID = DEFAULT_TYPE_ID,
  DEFAULT_TYPE = DEFAULT_TYPE,
  ID_TYPE_MAP = ID_TYPE_MAP,
  TYPE_ID_MAP = TYPE_ID_MAP,
  TYPE_EXT_MAP = TYPE_EXT_MAP,
}
