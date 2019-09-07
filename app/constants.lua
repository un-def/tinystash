local _M = {}


local AUDIO = 'audio'
local VOICE = 'voice'
local VIDEO = 'video'
local VIDEO_NOTE = 'video_note'
local PHOTO = 'photo'
local STICKER = 'sticker'
local DOCUMENT = 'document'


_M.TG_TYPES = {
  AUDIO = AUDIO,
  VOICE = VOICE,
  VIDEO = VIDEO,
  VIDEO_NOTE = VIDEO_NOTE,
  PHOTO = PHOTO,
  STICKER = STICKER,
  DOCUMENT = DOCUMENT,
}

_M.TG_TYPES_EXTENSIONS_MAP = {
  [VOICE] = 'ogg',   -- it should be .opus, but nobody respects RFCs
  [VIDEO] = 'mp4',
  [VIDEO_NOTE] = 'mp4',
  [PHOTO] = 'jpg',
}

_M.TG_TYPES_MEDIA_TYPES_MAP = {
  [VOICE] = 'audio/ogg',
  [VIDEO] = 'video/mp4',
  [VIDEO_NOTE] = 'video/mp4',
  [PHOTO] = 'image/jpeg',
}

_M.TG_CHAT_PRIVATE = 'private'

_M.TG_API_HOST = 'api.telegram.org'

_M.TG_MAX_FILE_SIZE = 20971520

_M.GET_FILE_MODES = {
  DOWNLOAD = 'dl',
  INLINE = 'il',
  LINKS = 'ln',
}

_M.CHUNK_SIZE = 8192


return _M
