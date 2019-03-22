local http = require('resty.http')
local template = require('resty.template')
local json = require('cjson.safe')

local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local render_link_factory = require('app.views.helpers').render_link_factory
local config = require('config.app')


local log = utils.log
local exit = utils.exit
local escape_uri = utils.escape_uri
local guess_extension = utils.guess_extension

local TG_TYPES = constants.TG_TYPES
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local TG_API_HOST = constants.TG_API_HOST
local GET_FILE_MODES = constants.GET_FILE_MODES
local CHUNK_SIZE = constants.CHUNK_SIZE

local tg_token = config.tg.token
local tg_request_timeout = config.tg.request_timeout * 1000


local request_tg_server = function(http_obj, params, decode_json)
  -- params table mutation!
  params.path = params.path:format(tg_token)
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


return {

  GET = function(tiny_id, mode, file_name)
    -- decode tinyid
    local tiny_id_params, tiny_id_err = tinyid.decode(tiny_id)
    if not tiny_id_params then
      log(ngx.INFO, 'tiny_id decode error: %s', tiny_id_err)
      exit(ngx.HTTP_NOT_FOUND)
    end

    local http_obj = http.new()
    http_obj:set_timeout(tg_request_timeout)
    local res, err, params

    -- get file info
    params = {
      path = '/bot%s/getFile',
      query = 'file_id=' .. tiny_id_params.file_id,
    }
    res, err = request_tg_server(http_obj, params, true)
    if not res then
      log(ngx.ERR, 'tg api request error: %s', err)
      exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
    end
    if not res.ok then
      log(ngx.INFO, 'tg api response is not "ok": %s', res.description)
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
      log(ngx.ERR, 'tg file storage request error: %s', err)
      exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
    end
    if res.status ~= ngx.HTTP_OK then
      log(ngx.ERR, 'tg file storage response status %s != 200', res.status)
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

    if mode == GET_FILE_MODES.LINKS then
      -- /ln/ -> render links page
      ngx.header['Content-Type'] = 'text/html'
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
      if not file_name or #file_name < 1 then
        file_name = tiny_id .. (extension or '')
      end
      local content_disposition
      if mode == GET_FILE_MODES.DOWNLOAD then
        content_disposition = 'attachment'
      else
        content_disposition = 'inline'
      end

      ngx.header['Content-Type'] = media_type
      ngx.header['Content-Disposition'] = ("%s; filename*=utf-8''%s"):format(
        content_disposition, escape_uri(file_name, true))
      ngx.header['Content-Length'] = file_size

      local chunk
      while true do
        chunk, err = res.body_reader(CHUNK_SIZE)
        if err then
          log(ngx.ERR, 'tg file storage read error: %s', err)
          break
        end
        if not chunk then break end
        ngx.print(chunk)
      end

    end

    -- put connection to connection pool
    http_obj:set_keepalive()

  end

}
