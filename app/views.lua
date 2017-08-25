local http = require('resty.http')
local template = require('resty.template')
local json = require('cjson.safe')

local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')

local config = require('config')

local log = utils.log
local exit = utils.exit
local guess_media_type = utils.guess_media_type
local guess_extension = utils.guess_extension

local TG_TYPES = constants.TG_TYPES
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local TG_API_HOST = constants.TG_API_HOST
local MAX_FILE_SIZE = constants.MAX_FILE_SIZE
local MAX_FILE_SIZE_AS_TEXT = constants.MAX_FILE_SIZE_AS_TEXT
local GET_FILE_MODES = constants.GET_FILE_MODES
local CHUNK_SIZE = constants.CHUNK_SIZE


local render_to_string = function(template_, context, plain)
  return template.compile(template_, nil, plain)(context)
end

local render_link_factory = function(tiny_id)
  local link_template = ('%s/%%s/%s'):format(config.link_url_prefix, tiny_id)
  return function(mode)
    return link_template:format(mode)
  end
end


local M = {}


M.main = function()
  template.render('web/main.html', {
    title = 'Welcome',
    bot_username = config.tg.bot_username,
  })
end


M.webhook = function(secret)
  if secret ~= (config.tg.webhook_secret or config.tg.token) then
    exit(ngx.HTTP_NOT_FOUND)
  end
  ngx.req.read_body()
  local req_body = ngx.req.get_body_data()
  log(req_body)

  local req_json = json.decode(req_body)
  local message = req_json and req_json.message
  if not message then
    exit(ngx.HTTP_OK)
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
    local media_type, media_type_id = guess_media_type(file_obj, file_obj_type)
    log('file_obj_type: %s', file_obj_type)
    log('media_type: %s -> %s (%s)',
      file_obj.mime_type, media_type, media_type_id)
    log('file_id: %s (%s bytes)', file_obj.file_id, file_obj.file_size)
    if file_obj.file_size and file_obj.file_size > MAX_FILE_SIZE then
      response_text = render_to_string('bot/err-file-too-big.txt', {
        max_file_size = MAX_FILE_SIZE_AS_TEXT,
      })
    else
      local tiny_id = tinyid.encode{
        file_id = file_obj.file_id,
        media_type_id = media_type_id,
      }
      log('tiny_id: %s', tiny_id)
      local extension = guess_extension{
        file_obj = file_obj,
        file_obj_type = file_obj_type,
        media_type = media_type,
      }
      response_text = render_to_string('bot/ok-links.txt', {
        modes = GET_FILE_MODES,
        render_link = render_link_factory(tiny_id),
        extension = extension,
      })
    end
  else
    response_text = render_to_string('bot/err-no-file.txt')
  end

  local params = {
    method = 'sendMessage',
    chat_id = message.from.id,
    text = response_text,
    parse_mode = 'markdown',
  }
  ngx.header['Content-Type'] = 'application/json'
  ngx.print(json.encode(params))
end


M.get_file = function(tiny_id, mode)
  -- decode tinyid
  local tiny_id_params, tiny_id_err = tinyid.decode(tiny_id)
  if not tiny_id_params then
    log('tiny_id decode error: %s', tiny_id_err)
    exit(ngx.HTTP_NOT_FOUND)
  end

  -- get file info
  local httpc = http.new()
  httpc:set_timeout(30000)
  local res, err
  local uri = ('https://%s/bot%s/getFile?file_id=%s'):format(
    TG_API_HOST, config.tg.token, tiny_id_params.file_id)
  res, err = httpc:request_uri(uri)
  if not res then
    log(err)
    exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
  end
  log(res.body)
  local res_json = json.decode(res.body)
  if not res_json.ok then
    log(res_json.description)
    exit(ngx.HTTP_NOT_FOUND, res_json.description)
  end

  -- connect to tg file storage
  local file_path = res_json.result.file_path
  local path = ('/file/bot%s/%s'):format(config.tg.token, file_path)
  httpc:connect(TG_API_HOST, 443)
  httpc:ssl_handshake(nil, TG_API_HOST, true)
  res, err = httpc:request({path = utils.escape_uri(path)})
  if not res then
    log(err)
    exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
  end

  local file_name
  if mode == GET_FILE_MODES.DOWNLOAD or mode == GET_FILE_MODES.LINKS then
    file_name = utils.get_basename(file_path)
    -- fix voice message file .oga extension
    if file_path:match('^voice/.+%.oga$') then
      file_name = ('%s.%s'):format(
        utils.split_ext(file_name), TG_TYPES_EXTENSIONS_MAP[TG_TYPES.VOICE])
    end
  end

  local media_type = tiny_id_params.media_type or 'application/octet-stream'

  if mode == GET_FILE_MODES.LINKS then
    -- /ln/ -> render links page
    local extension = guess_extension{
      file_name = file_name,
      media_type = media_type,
    }
    template.render('web/file-links.html', {
      title = file_name,
      file_name = file_name,
      media_type = media_type,
      modes = GET_FILE_MODES,
      render_link = render_link_factory(tiny_id),
      extension = extension,
    })
  else
    -- /dl/ or /il/ -> stream file content from tg file storage
    local content_disposition
    if mode == GET_FILE_MODES.DOWNLOAD then
      content_disposition = ('attachment; filename="%s"'):format(file_name)
    else
      content_disposition = 'inline'
    end

    ngx.header['Content-Type'] = media_type
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
      ngx.print(chunk)
    end

  end

  -- put connection to connection pool
  httpc:set_keepalive()

end


return M
