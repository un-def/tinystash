local http = require('resty.http')
local json = require('cjson.safe')
local base58 = require('basex').base58bitcoin

local cipher = require('cipher')
local utils = require('utils')
local config = require('config')


local M = {}

M.main = function()
  ngx.say('tiny[stash]')
end

M.webhook = function()
  ngx.req.read_body()
  local req_body = ngx.req.get_body_data()
  utils.log(req_body)

  local req_json = json.decode(req_body)
  local message = req_json and req_json.message
  if not message then
    ngx.exit(ngx.HTTP_OK)
  end

  local file_obj, response_text
  if message.audio then
    file_obj = message.audio
  elseif message.video then
    file_obj = message.video
  elseif message.voice then
    file_obj = message.voice
  elseif message.sticker then
    file_obj = message.sticker
  elseif message.photo then
    file_obj = message.photo[#message.photo]
  elseif message.document then
    file_obj = message.document
  end

  if file_obj and file_obj.file_id then
    utils.log('mime_type: %s', file_obj.mime_type)
    utils.log('file_id: %s', file_obj.file_id)
    local file_id_bytes = utils.decode_urlsafe_base64(file_obj.file_id)
    utils.log('file_id length: %d   bytes size: %d', #file_obj.file_id, #file_id_bytes)
    local tiny_id_src = string.char(#file_id_bytes) .. file_id_bytes
    local tiny_id_bytes = cipher:encrypt(tiny_id_src)
    local tiny_id = base58:encode(tiny_id_bytes)
    utils.log('tiny_id length: %d   bytes size: %d', #tiny_id, #tiny_id_bytes)
    response_text = config.link_url_prefix .. tiny_id
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

M.encrypt = function()
  -- TODO: obsolete version; move webhook tiny_id generation code to helper and reuse there
  local to_encrypt_bytes = utils.decode_urlsafe_base64(ngx.var.to_encrypt)
  if not to_encrypt_bytes then
    ngx.exit(ngx.HTTP_NOT_FOUND)
  end
  local encrypted_bytes = cipher:encrypt(to_encrypt_bytes)
  local encrypted = base58:encode(encrypted_bytes)
  ngx.say(('%s://%s/decrypt/%s'):format(ngx.var.scheme, ngx.var.host, encrypted))
end

M.decrypt = function()
  local tiny_id_bytes = base58:decode(ngx.var.tiny_id)
  local tiny_id_src = cipher:decrypt(tiny_id_bytes)
  local file_id_len = string.byte(tiny_id_src:sub(1, 1))
  local file_id_bytes = tiny_id_src:sub(2, file_id_len+1)
  local file_id = utils.encode_urlsafe_base64(file_id_bytes)
  local httpc = http.new()
  httpc:set_timeout(30000)
  local uri = 'https://api.telegram.org/bot' .. config.token .. '/getFile?file_id=' .. file_id
  local res, err = httpc:request_uri(uri)
  if res then
    utils.log(res.body)
    local res_json = json.decode(res.body)
    if not res_json.ok then
      ngx.say(res_json.description)
      ngx.exit(ngx.HTTP_BAD_REQUEST)
    else
      local file_path = res_json.result.file_path
      local path = '/file/bot' .. config.token .. '/' .. file_path
      httpc:connect('api.telegram.org', 443)
      local proxy_res, proxy_err = httpc:request({path = path})
      if proxy_res then
        proxy_res.headers['Content-Disposition'] = 'inline'
        httpc:proxy_response(proxy_res)
        httpc:set_keepalive()
      else
        ngx.say(proxy_err)
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
      end
    end
  else
    ngx.say(err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end
end

return M
