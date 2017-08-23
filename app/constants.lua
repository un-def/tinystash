local M = {}


local AUDIO = 'audio'
local VOICE = 'voice'
local VIDEO = 'video'
local VIDEO_NOTE = 'video_note'
local PHOTO = 'photo'
local STICKER = 'sticker'
local DOCUMENT = 'document'


M.TG_TYPES = {
  AUDIO = AUDIO,
  VOICE = VOICE,
  VIDEO = VIDEO,
  VIDEO_NOTE = VIDEO_NOTE,
  PHOTO = PHOTO,
  STICKER = STICKER,
  DOCUMENT = DOCUMENT,
}

M.TG_TYPES_EXTENSIONS_MAP = {
  [VOICE] = 'ogg',   -- it should be .opus, but nobody respects RFCs
  [VIDEO] = 'mp4',
  [VIDEO_NOTE] = 'mp4',
  [PHOTO] = 'jpg',
  [STICKER] = 'webp',
}

M.TG_TYPES_MEDIA_TYPES_MAP = {
  [VOICE] = 'audio/ogg',
  [VIDEO] = 'video/mp4',
  [VIDEO_NOTE] = 'video/mp4',
  [PHOTO] = 'image/jpeg',
  [STICKER] = 'image/webp',
}

M.GET_FILE_MODES = {
  DOWNLOAD = 'dl',
  INLINE = 'il',
}

M.TG_API_HOST = 'api.telegram.org'

M.MAX_FILE_SIZE = 20971520
M.MAX_FILE_SIZE_AS_TEXT = '20 MiB'

M.CHUNK_SIZE = 8192


return M
