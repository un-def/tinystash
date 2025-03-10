local base58 = require('basex').base58bitcoin

local cipher = require('app.cipher')
local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local tg = require('app.tg')
local helpers = require('app.views.helpers')
local DEFAULT_MEDIA_TYPE = require('app.mediatypes').DEFAULT_TYPE

local string_match = string.match
local string_format = string.format

local ngx_var = ngx.var
local ngx_print = ngx.print
local ngx_header = ngx.header
local ngx_exit = ngx.exit
local ngx_req = ngx.req
local ngx_INFO = ngx.INFO
local ngx_ERR = ngx.ERR
local ngx_HTTP_NOT_MODIFIED = ngx.HTTP_NOT_MODIFIED
local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY

local cipher_encrypt = cipher.encrypt
local cipher_decrypt = cipher.decrypt

local log = utils.log
local error = utils.error
local escape_uri = utils.escape_uri
local unescape_ext = utils.unescape_ext
local guess_extension = utils.guess_extension
local parse_media_type = utils.parse_media_type
local format_file_size = utils.format_file_size

local tg_client = tg.client

local render_link_factory = helpers.render_link_factory
local render = helpers.render

local TG_TYPES = constants.TG_TYPES
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local GET_FILE_MODES = constants.GET_FILE_MODES
local CHUNK_SIZE = constants.CHUNK_SIZE


local unquote_etag = function(etag)
  etag = string_match(etag, '^"(.+)"$')
  if not etag or #etag == 0 then return nil end
  return etag
end

local encode_etag = function(etag)
  etag = unquote_etag(etag)
  if not etag then return nil end
  etag = base58:encode(cipher_encrypt(etag))
  return string_format('"%s"', etag)
end

local decode_etag = function(etag)
  etag = unquote_etag(etag)
  if not etag then return nil end
  etag = base58:decode(etag)
  if not etag then return nil end
  etag = cipher_decrypt(etag)
  if not etag then return nil end
  return string_format('"%s"', etag)
end


return {

  GET = function(tiny_id, mode, file_name)
    -- decode tiny_id
    local tiny_id_params, tiny_id_err = tinyid.decode(tiny_id)
    if not tiny_id_params then
      log(ngx_INFO, 'tiny_id decode error: %s', tiny_id_err)
      return error(ngx_HTTP_NOT_FOUND)
    end
    -- get file info
    local client = tg_client()
    local resp, err = client:get_file(tiny_id_params.file_id)
    client:close()
    if err then
      log(ngx_ERR, 'tg api request error: %s', err)
      return error(ngx_HTTP_BAD_GATEWAY)
    end
    if not resp.ok then
      log(ngx_INFO, 'tg api response is not "ok": %s', resp.description)
      return error(ngx_HTTP_NOT_FOUND)
    end
    local file_path = resp.result.file_path
    local file_size = resp.result.file_size
    local media_type = tiny_id_params.media_type or DEFAULT_MEDIA_TYPE
    local extension
    -- getFile right after upload returns File without file_path field
    if file_path and file_path:match('^voice/.+%.oga$') then
    -- fix voice message file .oga extension
      extension = '.' .. TG_TYPES_EXTENSIONS_MAP[TG_TYPES.VOICE]
    else
      extension = guess_extension{
        file_name = file_path and unescape_ext(file_path),
        media_type = media_type,
      }
    end

    -- /ln/ -> render links page

    if mode == GET_FILE_MODES.LINKS then
      render('web/file-links.html', {
        title = tiny_id,
        file_size = format_file_size(file_size),
        media_type = media_type,
        modes = GET_FILE_MODES,
        render_link = render_link_factory(tiny_id),
        extension = extension,
      })
      return
    end

    -- /dl/ or /il/ -> stream file content from tg file storage

    if not file_path then
      return error(ngx_HTTP_BAD_GATEWAY, 'upstream did not return a file path')
    end
    -- connect to tg file storage
    local etag
    local encoded_etag = ngx_var.http_if_none_match
    if type(encoded_etag) == 'string' then
      etag = decode_etag(encoded_etag)
    end
    resp, err = client:request_file(file_path, etag)
    if err then
      client:close()
      log(ngx_ERR, 'tg file storage request error: %s', err)
      return error(ngx_HTTP_BAD_GATEWAY)
    end
    local res_status = resp.status
    if res_status == ngx_HTTP_NOT_MODIFIED then
      client:close()
      return ngx_exit(ngx_HTTP_NOT_MODIFIED)
    end

    if not file_name or #file_name < 1 then
      file_name = tiny_id .. (extension or '')
    end
    local content_disposition
    if mode == GET_FILE_MODES.DOWNLOAD then
      content_disposition = 'attachment'
    else
      content_disposition = 'inline'
    end

    local content_type, media_type_table
    local query = ngx_req.get_uri_args()
    local overridden_media_type = query.mt
    if type(overridden_media_type) == 'string' then
      media_type_table, err = parse_media_type(overridden_media_type)
      if not media_type_table then
        log(ngx_INFO, 'invalid overridden media type: %s, error: %s', overridden_media_type, err)
      else
        content_type = overridden_media_type
      end
    end
    if not content_type then
      content_type = media_type
    end
    if not media_type_table then
      media_type_table = parse_media_type(media_type)
    end
    if media_type_table[1] == 'text' then
      content_type = content_type .. '; charset=utf-8'
    end
    ngx_header['content-type'] = content_type
    ngx_header['content-disposition'] = ("%s; filename*=utf-8''%s"):format(
      content_disposition, escape_uri(file_name, true))
    ngx_header['content-length'] = file_size
    etag = resp.headers['etag']
    if type(etag) == 'string' then
      ngx_header['etag'] = encode_etag(etag)
    end

    local chunk
    while true do
      chunk, err = resp.body_reader(CHUNK_SIZE)
      if err then
        log(ngx_ERR, 'tg file storage read error: %s', err)
        break
      end
      if not chunk then break end
      ngx_print(chunk)
    end

    client:close()

  end

}
