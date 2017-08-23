local DEFAULT_TYPE_ID = 0

-- keep this array dense!
local MEDIA_TYPES = {
  -- audio types
  [1] = {'audio/mpeg', 'mp3'},
  [2] = {'audio/mp4', 'm4a'},
  [3] = {'audio/flac', 'flac'},
  [4] = {'audio/ogg', 'ogg'},
  -- [5] = {},   -- next index
}


local ID_TYPE_MAP = {}
local TYPE_ID_MAP = {}
local TYPE_EXT_MAP = {}


for media_type_id = 1, #MEDIA_TYPES do
  local media_type, extension = unpack(MEDIA_TYPES[media_type_id])
  TYPE_ID_MAP[media_type] = media_type_id
  ID_TYPE_MAP[media_type_id] = media_type
  TYPE_EXT_MAP[media_type] = extension
end


return {
  DEFAULT_TYPE_ID = DEFAULT_TYPE_ID,
  ID_TYPE_MAP = ID_TYPE_MAP,
  TYPE_ID_MAP = TYPE_ID_MAP,
  TYPE_EXT_MAP = TYPE_EXT_MAP,
}
