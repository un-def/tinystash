local template = require('resty.template')
local json = require('cjson.safe')

local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local render_link_factory = require('app.views.helpers').render_link_factory
local config = require('config.app')


local log = utils.log
local exit = utils.exit
local guess_media_type = utils.guess_media_type
local guess_extension = utils.guess_extension

local TG_TYPES = constants.TG_TYPES
local TG_CHAT_PRIVATE = constants.TG_CHAT_PRIVATE
local TG_MAX_FILE_SIZE = constants.TG_MAX_FILE_SIZE
local GET_FILE_MODES = constants.GET_FILE_MODES

local tg_token = config.tg.token
local tg_bot_username = config.tg.bot_username
local tg_webhook_secret = config.tg.webhook_secret or tg_token
local hide_image_download_link = config.hide_image_download_link


local render_to_string = function(template_, context, plain)
  return template.compile(template_, nil, plain)(context)
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


return {

  POST = function(secret)
    if secret ~= tg_webhook_secret then
      exit(ngx.HTTP_NOT_FOUND)
    end
    ngx.req.read_body()
    local req_body = ngx.req.get_body_data()
    local req_json = json.decode(req_body)
    log('webhook request: %s', req_json and json.encode(req_json) or req_body)
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
      if is_groupchat and bot_username ~= tg_bot_username then
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
    local hide_download_link = (hide_image_download_link
                                and media_type
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

}
