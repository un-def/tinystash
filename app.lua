local http = require('resty.http')
local json = require('cjson.safe')

local tinyid = require('tinyid')
local utils = require('utils')
local config = require('config')


local M = {
  SUPPORTED_TG_TYPES = {'audio', 'voice', 'video', 'video_note',
                        'photo', 'sticker', 'document'},
  MAX_FILE_SIZE = 20971520,
  MAX_FILE_SIZE_AS_TEXT = '20 MiB',
  CHUNK_SIZE = 8192,
}


M.main = function()
  ngx.say('tiny[stash]')
end


M.webhook = function(self)
  ngx.req.read_body()
  local req_body = ngx.req.get_body_data()
  utils.log(req_body)

  local req_json = json.decode(req_body)
  local message = req_json and req_json.message
  if not message then
    ngx.exit(ngx.HTTP_OK)
  end

  local file_obj, response_text
  for _, type_name in ipairs(self.SUPPORTED_TG_TYPES) do
    file_obj = message[type_name]
    if file_obj then
      if type_name == 'photo' then
        file_obj = file_obj[#file_obj]
      end
      break
    end
  end

  if file_obj and file_obj.file_id then
    utils.log('mime_type: %s', file_obj.mime_type)
    utils.log('file_id: %s', file_obj.file_id)
    utils.log('file_size: %s', file_obj.file_size)
    if file_obj.file_size and file_obj.file_size > self.MAX_FILE_SIZE then
      response_text = ('The file is too big. Maximum file size is %s.'):format(
        self.MAX_FILE_SIZE_AS_TEXT)
    else
      local tiny_id = tinyid.encode({file_id = file_obj.file_id})
      response_text = config.link_url_prefix .. tiny_id
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


M.decrypt = function(self)
  local tiny_id_data, tiny_id_err = tinyid.decode(ngx.var.tiny_id)
  if not tiny_id_data then
    utils.log('tiny_id decode error: %s', tiny_id_err)
    ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  local httpc = http.new()
  httpc:set_timeout(30000)
  local res, err

  local uri = 'https://api.telegram.org/bot' .. config.token ..
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
  local path = '/file/bot' .. config.token .. '/' .. file_path
  httpc:connect('api.telegram.org', 443)
  res, err = httpc:request({path = path})
  if not res then
    ngx.say(err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  local file_name = file_path:match('/([^/]*)$') or file_path
  local content_disposition = (
    'attachment; filename="%s"'):format(file_name)
  ngx.header['Content-Disposition'] = content_disposition
  ngx.header['Content-Type'] = 'application/octet-stream'
  ngx.header['Content-Length'] = res.headers['Content-Length']

  local chunk
  while true do
    chunk, err = res.body_reader(self.CHUNK_SIZE)
    if err then
      utils.log(ngx.ERR, err)
      break
    end
    if not chunk then break end
    ngx.print(chunk)
  end

end


return M
