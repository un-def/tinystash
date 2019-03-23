local template = require('resty.template')

local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local tg = require('app.tg')
local render_link_factory = require('app.views.helpers').render_link_factory


local log = utils.log
local exit = utils.exit
local escape_uri = utils.escape_uri
local guess_extension = utils.guess_extension
local parse_media_type = utils.parse_media_type

local prepare_connection = tg.prepare_connection
local request_tg_server = tg.request_tg_server

local TG_TYPES = constants.TG_TYPES
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local GET_FILE_MODES = constants.GET_FILE_MODES
local CHUNK_SIZE = constants.CHUNK_SIZE


return {

  GET = function(tiny_id, mode, file_name)
    -- decode tinyid
    local tiny_id_params, tiny_id_err = tinyid.decode(tiny_id)
    if not tiny_id_params then
      log(ngx.INFO, 'tiny_id decode error: %s', tiny_id_err)
      exit(ngx.HTTP_NOT_FOUND)
    end

    local conn, res, err, params
    conn, err = prepare_connection()
    if not conn then
      log(ngx.ERR, 'tg api request error: %s', err)
      exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
    end

    -- get file info
    params = {
      path = '/bot%s/getFile',
      query = 'file_id=' .. tiny_id_params.file_id,
    }
    res, err = request_tg_server(conn, params, true)
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
    res, err = request_tg_server(conn, params)
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

      local content_type = media_type
      if parse_media_type(media_type)[1] == 'text' then
        content_type = content_type .. '; charset=utf-8'
      end
      ngx.header['content-type'] = content_type
      ngx.header['content-disposition'] = ("%s; filename*=utf-8''%s"):format(
        content_disposition, escape_uri(file_name, true))
      ngx.header['content-length'] = file_size

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
    conn:set_keepalive()

  end

}
