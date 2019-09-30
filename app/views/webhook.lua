local json = require('cjson.safe')

local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local helpers = require('app.views.helpers')
local get_file_from_message = require('app.tg').get_file_from_message

local config = require('app.config')


local ngx_say = ngx.say
local ngx_req = ngx.req
local ngx_header = ngx.header
local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND

local json_encode = json.encode
local json_decode = json.decode

local log = utils.log
local error = utils.error
local guess_media_type = utils.guess_media_type
local guess_extension = utils.guess_extension

local TG_CHAT_PRIVATE = constants.TG_CHAT_PRIVATE
local TG_MAX_FILE_SIZE = constants.TG_MAX_FILE_SIZE
local GET_FILE_MODES = constants.GET_FILE_MODES

local tg_bot_username = config.tg.bot_username
local tg_webhook_secret = config._processed.tg_webhook_secret
local hide_image_download_link = config.hide_image_download_link

local link_url_prefix = config._processed.link_url_prefix
local enable_upload = config._processed.enable_upload
local render_link_factory = helpers.render_link_factory
local render_to_string = helpers.render_to_string


local send_webhook_response = function(message, template_path, context)
  local chat = message.chat
  -- context table mutation!
  if chat.type ~= TG_CHAT_PRIVATE then
    context = context or {}
    context.user = message.from
  end
  ngx_header['content-type'] = 'application/json'
  ngx_say(json_encode{
    method = 'sendMessage',
    chat_id = chat.id,
    text = render_to_string(template_path, context),
    parse_mode = 'markdown',
    disable_web_page_preview = true,
  })
end


return {

  initial = function(secret)
    if secret ~= tg_webhook_secret then
      return error(ngx_HTTP_NOT_FOUND)
    end
  end,

  POST = function()
    ngx_req.read_body()
    local req_body = ngx_req.get_body_data()
    local req_json = json_decode(req_body)
    log('webhook request: %s', req_json and json_encode(req_json) or req_body)
    local message = req_json and req_json.message
    if not message or not message.chat then
      return
    end

    local is_groupchat = message.chat.type ~= TG_CHAT_PRIVATE

    if message.text then
      local command, bot_username = message.text:match('^/([%w_]+)@?([%w_]*)')
      if not command then
        return send_webhook_response(message, 'bot/err-no-file.txt')
      end
      -- ignore groupchat commands to other bots / commands without bot username
      if is_groupchat and bot_username ~= tg_bot_username then
        return
      end
      return send_webhook_response(message, 'bot/ok-help.txt', {
        link_url_prefix = link_url_prefix,
        enable_upload = enable_upload,
      })
    end

    -- tricky way to ignore groupchat service messages (e.g., new_chat_member)
    if is_groupchat and not message.reply_to_message then
      return
    end

    local file, err = get_file_from_message(message)
    if not file then
      log(err)
      return send_webhook_response(message, 'bot/err-no-file.txt')
    end

    local file_obj = file.object
    local file_obj_type = file.type

    if not file_obj.file_id then
      log('no file_id')
      return send_webhook_response(message, 'bot/err-no-file.txt')
    end

    if file_obj.file_size and file_obj.file_size > TG_MAX_FILE_SIZE then
      return send_webhook_response(message, 'bot/err-file-too-big.txt')
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
    return send_webhook_response(message, 'bot/ok-links.txt', {
      modes = GET_FILE_MODES,
      render_link = render_link_factory(tiny_id),
      extension = extension,
      hide_download_link = hide_download_link,
    })

  end

}
