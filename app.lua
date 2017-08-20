local http = require('resty.http')
local json = require('cjson.safe')

local tinyid = require('tinyid')
local mediatypes = require('mediatypes')
local utils = require('utils')
local config = require('config')

local print = ngx.print
local log = utils.log


local TG_API_HOST = 'api.telegram.org'

local TG_TYPES = {
  AUDIO = 'audio',
  VOICE = 'voice',
  VIDEO = 'video',
  VIDEO_NOTE = 'video_note',
  PHOTO = 'photo',
  STICKER = 'sticker',
  DOCUMENT = 'document',
}

local TG_TYPES_EXTENSIONS_MAP = {
  [TG_TYPES.VOICE] = 'ogg',   -- it should be .opus, but nobody respects RFCs
  [TG_TYPES.VIDEO] = 'mp4',
  [TG_TYPES.VIDEO_NOTE] = 'mp4',
  [TG_TYPES.PHOTO] = 'jpg',
  [TG_TYPES.STICKER] = 'webp',
}

local TG_TYPES_MEDIA_TYPES_MAP = {
  [TG_TYPES.VOICE] = 'audio/ogg',
  [TG_TYPES.VIDEO] = 'video/mp4',
  [TG_TYPES.VIDEO_NOTE] = 'video/mp4',
  [TG_TYPES.PHOTO] = 'image/jpeg',
  [TG_TYPES.STICKER] = 'image/webp',
}

local GET_FILE_MODES = {
  DOWNLOAD = 'dl',
  INLINE = 'il',
}

local MAX_FILE_SIZE = 20971520
local MAX_FILE_SIZE_AS_TEXT = '20 MiB'

local CHUNK_SIZE = 8192


local M = {}
local views = {}
M.views = views
M.__index = M
setmetatable(views, M)


---- views ----

views.main = function()
  print('tiny[stash]')
end


views.webhook = function(self, secret)
  if secret ~= (config.tg_webhook_secret or config.tg_token) then
    self:exit(ngx.HTTP_NOT_FOUND)
  end
  ngx.req.read_body()
  local req_body = ngx.req.get_body_data()
  log(req_body)

  local req_json = json.decode(req_body)
  local message = req_json and req_json.message
  if not message then
    self:exit(ngx.HTTP_OK)
  end

  local file_obj, file_obj_type, response_text
  for _, _file_obj_type in pairs(TG_TYPES) do
    file_obj = message[_file_obj_type]
    if file_obj then
      file_obj_type = _file_obj_type
      if file_obj_type == TG_TYPES.PHOTO then
        file_obj = file_obj[#file_obj]
      end
      break
    end
  end

  if file_obj and file_obj.file_id then
    local media_type = self:guess_media_type(file_obj, file_obj_type)
    log('file_obj_type: %s  |  media_type: %s', file_obj_type, media_type)
    log('file_id: %s  |  file_size: %s', file_obj.file_id, file_obj.file_size)
    if file_obj.file_size and file_obj.file_size > MAX_FILE_SIZE then
      response_text = ('The file is too big. Maximum file size is %s.'):format(
        MAX_FILE_SIZE_AS_TEXT)
    else
      local tiny_id = tinyid.encode{
        file_id = file_obj.file_id,
        media_type = media_type,
      }
      local extension = self:guess_extension(
        file_obj, file_obj_type, media_type)
      local link_template = ('%s/%%s/%s%s'):format(
        config.link_url_prefix, tiny_id, extension or '')
      local download_link = link_template:format(GET_FILE_MODES.DOWNLOAD)
      local inline_link = link_template:format(GET_FILE_MODES.INLINE)
      response_text = ([[
Inline link (view in browser):
%s

Download link:
%s
]]):format(inline_link, download_link)
    end
  else
    response_text = 'Send me picture, audio, video, or file.'
  end

  local params = {
    method = 'sendMessage',
    chat_id = message.from.id,
    text = response_text,
  }
  ngx.header['Content-Type'] = 'application/json'
  print(json.encode(params))
end


views.get_file = function(self, tiny_id, mode, extension)
  if extension == '' then extension = nil end
  local tiny_id_params, tiny_id_err = tinyid.decode(tiny_id)
  if not tiny_id_params then
    log('tiny_id decode error: %s', tiny_id_err)
    self:exit(ngx.HTTP_NOT_FOUND)
  end

  local httpc = http.new()
  httpc:set_timeout(30000)
  local res, err
  local uri = ('https://%s/bot%s/getFile?file_id=%s'):format(
    TG_API_HOST, config.tg_token, tiny_id_params.file_id)
  res, err = httpc:request_uri(uri)
  if not res then
    log(err)
    self:exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
  end

  log(res.body)
  local res_json = json.decode(res.body)
  if not res_json.ok then
    log(res_json.description)
    self:exit(ngx.HTTP_NOT_FOUND, res_json.description)
  end

  local file_path = res_json.result.file_path
  local path = ('/file/bot%s/%s'):format(config.tg_token, file_path)
  httpc:connect(TG_API_HOST, 443)
  httpc:ssl_handshake(nil, TG_API_HOST, true)
  res, err = httpc:request({path = utils.escape_uri(path)})
  if not res then
    log(err)
    self:exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
  end

  local media_type = tiny_id_params.media_type
  if not media_type and not extension then
    media_type = 'application/octet-stream'
  end

  local content_disposition
  if mode == GET_FILE_MODES.DOWNLOAD then
    local file_name = utils.get_basename(file_path)
    -- fix voice message file .oga extension
    if file_path:match('^voice/.+%.oga$') then
      file_name = ('%s.%s'):format(
        utils.split_ext(file_name), TG_TYPES_EXTENSIONS_MAP[TG_TYPES.VOICE])
    end
    content_disposition = ('attachment; filename="%s"'):format(file_name)
  elseif mode == GET_FILE_MODES.INLINE then
    content_disposition = 'inline'
  end

  if media_type then
    -- if not media_type -> fallback to nginx mime.types (detect type by uri)
    ngx.header['Content-Type'] = media_type
  end
  ngx.header['Content-Disposition'] = content_disposition
  ngx.header['Content-Length'] = res.headers['Content-Length']

  local chunk
  while true do
    chunk, err = res.body_reader(CHUNK_SIZE)
    if err then
      log(ngx.ERR, err)
      break
    end
    if not chunk then break end
    print(chunk)
  end

  httpc:set_keepalive()

end


---- app-specific helpers ----

M.exit = function(_, status, content)
  if not content then ngx.exit(status) end
  ngx.status = status
  ngx.header['Content-Type'] = 'text/plain'
  print(content)
  ngx.exit(ngx.HTTP_OK)
end


M.guess_media_type = function(_, file_obj, file_obj_type)
  return file_obj.mime_type or TG_TYPES_MEDIA_TYPES_MAP[file_obj_type]
end


M.guess_extension = function(_, file_obj, file_obj_type, media_type,
                             exclude_dot)
  local ext
  if file_obj.file_name then
    _, ext = utils.split_ext(file_obj.file_name, true)
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
