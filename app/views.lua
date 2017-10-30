local http = require('resty.http')
local template = require('resty.template')
local json = require('cjson.safe')

local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')

local config = require('config')

local log = utils.log
local exit = utils.exit
local escape_uri = utils.escape_uri
local guess_media_type = utils.guess_media_type
local guess_extension = utils.guess_extension

local TG_TYPES = constants.TG_TYPES
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local TG_CHAT_PRIVATE = constants.TG_CHAT_PRIVATE
local TG_API_HOST = constants.TG_API_HOST
local TG_MAX_FILE_SIZE = constants.TG_MAX_FILE_SIZE
local GET_FILE_MODES = constants.GET_FILE_MODES
local CHUNK_SIZE = constants.CHUNK_SIZE
local TIMEOUT = constants.TIMEOUT


local render_to_string = function(template_, context, plain)
  return template.compile(template_, nil, plain)(context)
end

local render_link_factory = function(tiny_id)
  local link_template = ('%s/%%s/%s'):format(config.link_url_prefix, tiny_id)
  return function(mode)
    return link_template:format(mode)
  end
end

local send_webhook_response = function(message, template_, context)
  local chat = message.chat
  -- context table mutation!
  if chat.type ~= TG_CHAT_PRIVATE then
    context = context or {}
    context.user = message.from
  end
  ngx.header['Content-Type'] = 'application/json'
  ngx.print(json.encode{
    method = 'sendMessage',
    chat_id = chat.id,
    text = render_to_string(template_, context),
    parse_mode = 'markdown',
    disable_web_page_preview = true,
  })
  exit(ngx.HTTP_OK)
end

local request_tg_server = function(http_obj, params, decode_json)
  -- params table mutation!
  params.path = params.path:format(config.tg.token)
  local res, err
  res, err = http_obj:connect(TG_API_HOST, 443)
  if not res then return nil, err end
  res, err = http_obj:ssl_handshake(nil, TG_API_HOST, true)
  if not res then return nil, err end
  res, err = http_obj:request(params)
  if not res then return nil, err end
  -- don't forget to call :close or :set_keepalive
  if not decode_json then return res end
  local body
  body, err = res:read_body()
  http_obj:set_keepalive()
  if not body then return nil, err end
  return json.decode(body)
end


local M = {}


M.main = function()
  template.render('web/main.html', {
    bot_username = config.tg.bot_username,
  })
end


M.webhook = function(secret)
  if secret ~= (config.tg.webhook_secret or config.tg.token) then
    exit(ngx.HTTP_NOT_FOUND)
  end
  ngx.req.read_body()
  local req_body = ngx.req.get_body_data()
  local req_json = json.decode(req_body)
  log(req_json and json.encode(req_json) or req_body)
  local message = req_json and req_json.message
  if not message then
    exit(ngx.HTTP_OK)
  end

  local is_groupchat = message.chat.type ~= TG_CHAT_PRIVATE

  if message.text then
    local command, bot_username = message.text:match('^/([%w_]+)@?([%w_]*)')
    if not command then
      send_webhook_response(message, 'bot/err-no-file.txt')
    end
    -- ignore groupchat commands to other bots / commands without bot username
    if is_groupchat and bot_username ~= config.tg.bot_username then
      exit(ngx.HTTP_OK)
    end
    send_webhook_response(message, 'bot/ok-help.txt')
  end

  -- tricky way to ignore groupchat service messages (e.g., new_chat_member)
  if is_groupchat and not message.reply_to_message then
    exit(ngx.HTTP_OK)
  end

  local file_obj, file_obj_type
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

  if not file_obj or not file_obj.file_id then
    send_webhook_response(message, 'bot/err-no-file.txt')
  end

  if file_obj.file_size and file_obj.file_size > TG_MAX_FILE_SIZE then
    send_webhook_response(message, 'bot/err-file-too-big.txt')
  end

  local media_type_id, media_type = guess_media_type(file_obj, file_obj_type)
  local tiny_id = tinyid.encode{
    file_id = file_obj.file_id,
    media_type_id = media_type_id,
  }
  local extension = guess_extension{
    file_obj = file_obj,
    file_obj_type = file_obj_type,
    media_type = media_type,
  }
  local hide_download_link = (config.hide_image_download_link
                              and media_type:sub(1, 6) == 'image/')
  log('file_obj_type: %s', file_obj_type)
  log('media_type: %s -> %s (%s)',
    file_obj.mime_type, media_type, media_type_id)
  log('file_id: %s (%s bytes)', file_obj.file_id, file_obj.file_size)
  log('tiny_id: %s', tiny_id)
  send_webhook_response(message, 'bot/ok-links.txt', {
    modes = GET_FILE_MODES,
    render_link = render_link_factory(tiny_id),
    extension = extension,
    hide_download_link = hide_download_link,
  })

end


M.get_file = function(tiny_id, mode)
  -- decode tinyid
  local tiny_id_params, tiny_id_err = tinyid.decode(tiny_id)
  if not tiny_id_params then
    log('tiny_id decode error: %s', tiny_id_err)
    exit(ngx.HTTP_NOT_FOUND)
  end

  local http_obj = http.new()
  http_obj:set_timeout(TIMEOUT)
  local res, err, params

  -- get file info
  params = {
    path = '/bot%s/getFile',
    query = 'file_id=' .. tiny_id_params.file_id,
  }
  res, err = request_tg_server(http_obj, params, true)
  if not res then
    log(err)
    exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
  end
  if not res.ok then
    log(res.description)
    exit(ngx.HTTP_NOT_FOUND, res.description)
  end

  local file_path = res.result.file_path

  -- connect to tg file storage
  params = {
    path = escape_uri('/file/bot%s/' .. file_path)
  }
  if mode == GET_FILE_MODES.LINKS then
    params.method = 'HEAD'
  else
    params.method = 'GET'
  end
  res, err = request_tg_server(http_obj, params)
  if not res then
    log(err)
    exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
  end
  if res.status ~= ngx.HTTP_OK then
    log('file response status %s != 200', res.status)
    exit(ngx.HTTP_NOT_FOUND)
  end

  local file_size = res.headers['Content-Length']
  local media_type = tiny_id_params.media_type or 'application/octet-stream'

  local extension
  -- fix voice message file .oga extension
  if file_path:match('^voice/.+%.oga$') then
    extension = '.' .. TG_TYPES_EXTENSIONS_MAP[TG_TYPES.VOICE]
  else
    extension = guess_extension{
      file_name = file_path,
      media_type = media_type,
    }
  end
  local file_name = tiny_id .. (extension or '')

  if mode == GET_FILE_MODES.LINKS then
    -- /ln/ -> render links page
    template.render('web/file-links.html', {
      title = tiny_id,
      file_size = file_size,
      media_type = media_type,
      modes = GET_FILE_MODES,
      render_link = render_link_factory(tiny_id),
      extension = extension,
    })
  else
    -- /dl/ or /il/ -> stream file content from tg file storage
    local content_disposition
    if mode == GET_FILE_MODES.DOWNLOAD then
      content_disposition = 'attachment'
    else
      content_disposition = 'inline'
    end

    ngx.header['Content-Type'] = media_type
    ngx.header['Content-Disposition'] = ('%s; filename="%s"'):format(
      content_disposition, file_name)
    ngx.header['Content-Length'] = file_size

    local chunk
    while true do
      chunk, err = res.body_reader(CHUNK_SIZE)
      if err then
        log(ngx.ERR, err)
        break
      end
      if not chunk then break end
      ngx.print(chunk)
    end

  end

  -- put connection to connection pool
  http_obj:set_keepalive()

end


return M
