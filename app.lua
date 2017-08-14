local http = require('resty.http')
local json = require('cjson.safe')

local tinyid = require('tinyid')
local utils = require('utils')
local config = require('config')


local TG_TYPES = {
  AUDIO = 'audio',
  VOICE = 'voice',
  VIDEO = 'video',
  VIDEO_NOTE = 'video_note',
  PHOTO = 'photo',
  STICKER = 'sticker',
  DOCUMENT = 'document',
}

local TG_TYPES_EXT = {
  [TG_TYPES.VOICE] = 'oga',
  [TG_TYPES.VIDEO] = 'mp4',
  [TG_TYPES.VIDEO_NOTE] = 'mp4',
  [TG_TYPES.PHOTO] = 'jpg',
  [TG_TYPES.STICKER] = 'webp',
}

local GET_FILE_MODES = {
  DOWNLOAD = 'dl',
  INLINE = 'il',
}

local MAX_FILE_SIZE = 20971520
local MAX_FILE_SIZE_AS_TEXT = '20 MiB'

local CHUNK_SIZE = 8192



local M = {}


M.main = function()
  ngx.say('tiny[stash]')
end


M.webhook = function(secret)
  if secret ~= (config.tg_webhook_secret or config.tg_token) then
    ngx.exit(ngx.HTTP_NOT_FOUND)
  end
  ngx.req.read_body()
  local req_body = ngx.req.get_body_data()
  utils.log(req_body)

  local req_json = json.decode(req_body)
  local message = req_json and req_json.message
  if not message then
    ngx.exit(ngx.HTTP_OK)
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
    utils.log('mime_type: %s', file_obj.mime_type)
    utils.log('file_id: %s', file_obj.file_id)
    utils.log('file_size: %s', file_obj.file_size)
    if file_obj.file_size and file_obj.file_size > MAX_FILE_SIZE then
      response_text = ('The file is too big. Maximum file size is %s.'):format(
        MAX_FILE_SIZE_AS_TEXT)
    else
      local tiny_id = tinyid.encode({file_id = file_obj.file_id})
      local link_template = ('%s/%%s/%s'):format(config.link_url_prefix,
                                                 tiny_id)
      local file_ext = TG_TYPES_EXT[file_obj_type]
      if file_obj.file_name then
        file_ext = utils.get_filename_ext(file_obj.file_name)
      end
      if file_ext then
        link_template = link_template .. '.' .. file_ext
      end
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
  ngx.print(json.encode(params))
end


M.get_file = function(tiny_id, mode, extension)
  if extension == '' then extension = nil end
  local tiny_id_data, tiny_id_err = tinyid.decode(tiny_id)
  if not tiny_id_data then
    utils.log('tiny_id decode error: %s', tiny_id_err)
    ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  local httpc = http.new()
  httpc:set_timeout(30000)
  local res, err

  local uri = 'https://api.telegram.org/bot' .. config.tg_token ..
              '/getFile?file_id=' .. tiny_id_data.file_id
  res, err = httpc:request_uri(uri)
  if not res then
    ngx.say(err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  utils.log(res.body)
  local res_json = json.decode(res.body)
  if not res_json.ok then
    ngx.say(res_json.description)
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end

  local file_path = res_json.result.file_path
  local path = '/file/bot' .. config.tg_token .. '/' .. file_path
  httpc:connect('api.telegram.org', 443)
  res, err = httpc:request({path = path})
  if not res then
    ngx.say(err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  if not extension then
    ngx.header['Content-Type'] = 'application/octet-stream'
  end
  local content_disposition
  if mode == GET_FILE_MODES.DOWNLOAD then
    local file_name = utils.get_basename(file_path)
    content_disposition = ('attachment; filename="%s"'):format(file_name)
  elseif mode == GET_FILE_MODES.INLINE then
    content_disposition = 'inline'
  end
  ngx.header['Content-Disposition'] = content_disposition
  ngx.header['Content-Length'] = res.headers['Content-Length']

  local chunk
  while true do
    chunk, err = res.body_reader(CHUNK_SIZE)
    if err then
      utils.log(ngx.ERR, err)
      break
    end
    if not chunk then break end
    ngx.print(chunk)
  end

end


return M
