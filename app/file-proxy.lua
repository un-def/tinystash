local base58 = require('basex').base58bitcoin

local cipher = require('app.cipher')
local utils = require('app.utils')
local constants = require('app.constants')
local tg = require('app.tg')

local string_match = string.match
local string_format = string.format

local ngx_req = ngx.req
local ngx_var = ngx.var
local ngx_print = ngx.print
local ngx_header = ngx.header
local ngx_exit = ngx.exit
local ngx_INFO = ngx.INFO
local ngx_ERR = ngx.ERR
local ngx_OK = ngx.OK
local ngx_HTTP_NOT_ALLOWED = ngx.HTTP_NOT_ALLOWED
local ngx_HTTP_NOT_MODIFIED = ngx.HTTP_NOT_MODIFIED
local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY

local cipher_encrypt = cipher.encrypt
local cipher_decrypt = cipher.decrypt

local log = utils.log
local guess_extension = utils.guess_extension
local unescape_ext = utils.unescape_ext
local escape_uri = utils.escape_uri
local parse_media_type = utils.parse_media_type

local tg_client = tg.client

local TG_TYPES = constants.TG_TYPES
local TG_TYPES_EXTENSIONS_MAP = constants.TG_TYPES_EXTENSIONS_MAP
local TG_FILE_PATH_HEADER = constants.TG_FILE_PATH_HEADER
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

local get_file = function(client, file_id, method)
  log('file_id: %s', file_id)
  local resp, err = client:get_file(file_id)
  if err then
    log(ngx_ERR, 'tg api request error: %s', err)
    return ngx_HTTP_BAD_GATEWAY
  end
  if not resp.ok then
    log(ngx_INFO, 'tg api response is not "ok": %s', resp.description)
    return ngx_HTTP_NOT_FOUND
  end
  local file_size = resp.result.file_size
  local file_path = resp.result.file_path
  if not file_path or #file_path == 0 then
    log(ngx_INFO, 'upstream did not return a file path')
    return ngx_HTTP_BAD_GATEWAY
  end

  local etag
  local encoded_etag = ngx_var.http_if_none_match
  if type(encoded_etag) == 'string' then
    etag = decode_etag(encoded_etag)
  end

  resp, err = client:request_file(file_path, etag, method)
  if err then
    log(ngx_ERR, 'tg file storage request error: %s', err)
    return ngx_HTTP_BAD_GATEWAY
  end
  if resp.status == ngx_HTTP_NOT_MODIFIED then
    return ngx_HTTP_NOT_MODIFIED
  end

  ngx_header['Content-Type'] = resp.headers['Content-Type']
  ngx_header['Content-Length'] = resp.headers['Content-Length'] or file_size
  etag = resp.headers['ETag']
  if type(etag) == 'string' then
    ngx_header['ETag'] = encode_etag(etag)
  end
  ngx_header[TG_FILE_PATH_HEADER] = file_path

  if method == 'GET' then
    local chunk
    while true do
      chunk, err = resp.body_reader(CHUNK_SIZE)
      if err then
        log(ngx_ERR, 'tg file storage read error: %s', err)
        break
      end
      if not chunk then
        break
      end
      ngx_print(chunk)
    end
  end

  return ngx_OK

end

local get_file_handler = function()
  -- query args:
  -- * file_id: string
  local method = ngx_req.get_method()
  if method ~= 'GET' and method ~= 'HEAD' then
    return ngx_exit(ngx_HTTP_NOT_ALLOWED)
  end
  local client = tg_client()
  local status = get_file(client, ngx_var.arg_file_id, method)
  client:close()
  return ngx_exit(status)
end

local get_file_header_filter = function()
  -- query args:
  -- * media_type: string
  -- * file_name: string
  -- * add_ext?: boolean
  -- * inline?: boolean
  local file_path = ngx_header[TG_FILE_PATH_HEADER]
  ngx.header[TG_FILE_PATH_HEADER] = nil

  local args, err = ngx_req.get_uri_args(10)
  if err ~= nil then
    log(ngx_ERR, "get_uri_args error: %s", err)
    return
  end

  local media_type = args.media_type
  local media_type_table = parse_media_type(media_type)
  if media_type_table then
    local content_type = media_type
    if media_type_table[1] == 'text' then
      content_type = content_type .. '; charset=utf-8'
    end
    ngx_header['Content-Type'] = content_type
  end

  local file_name = args.file_name
  if args.add_ext then
    local file_ext
    -- getFile right after upload returns File without file_path field
    if file_path:match('^voice/.+%.oga$') then
    -- fix voice message file .oga extension
      file_ext = '.' .. TG_TYPES_EXTENSIONS_MAP[TG_TYPES.VOICE]
    else
      file_ext = guess_extension{
        file_name = unescape_ext(file_path),
        media_type = media_type,
      }
    end
    if file_ext then
      file_name = file_name .. file_ext
    end
  end
  local disposition_type
  if args.inline then
    disposition_type = 'inline'
  else
    disposition_type = 'attachment'
  end
  ngx_header['Content-Disposition'] = string_format(
    "%s; filename*=utf-8''%s",
    disposition_type,
    escape_uri(file_name, true)
  )

end

return {
  get_file_handler = get_file_handler,
  get_file_header_filter = get_file_header_filter,
}
