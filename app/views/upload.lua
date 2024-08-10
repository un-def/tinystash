local json_encode = require('cjson.safe').encode
local parse_accept_header = require('httoolsp.headers').parse_accept_header

local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local helpers = require('app.views.helpers')
local file_form_uploader = require('app.uploader.file.form')
local file_direct_uploader = require('app.uploader.file.direct')
local url_form_uploader = require('app.uploader.url.form')
local url_direct_uploader = require('app.uploader.url.direct')
local config = require('app.config')


local ngx_redirect = ngx.redirect
local ngx_print = ngx.print
local ngx_say = ngx.say
local ngx_req = ngx.req
local ngx_req_get_headers = ngx_req.get_headers
local ngx_var = ngx.var
local ngx_header = ngx.header
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_HTTP_SEE_OTHER = ngx.HTTP_SEE_OTHER
local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND
local ngx_HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR

local enable_upload = config._processed.enable_upload
local enable_upload_api = config._processed.enable_upload_api
local tg_upload_chat_id = config.tg.upload_chat_id
local url_path_prefix = config._processed.url_path_prefix

local log = utils.log
local error = utils.error
local generate_random_hex_string = utils.generate_random_hex_string
local get_media_type_id = utils.get_media_type_id
local render_link_factory = helpers.render_link_factory
local render = helpers.render

local CSRFTOKEN_FIELD_NAME = constants.CSRFTOKEN_FIELD_NAME


local err_code_to_log_level = function(err_code)
  if err_code >= 500 then
    return ngx_ERR
  end
  return ngx_DEBUG
end


local MEDIA_TYPES = {
  'text/plain',
  'application/json',
}


return {

  initial = function(upload_type)
    if not enable_upload then
      return error(ngx_HTTP_NOT_FOUND)
    end
    return upload_type
  end,

  GET = function(upload_type)
    -- upload_type: file | text | url
    local path = ngx_var.request_uri
    local args_idx = path:find('?', 2, true)
    if args_idx then
      path = path:sub(1, args_idx - 1)
    end
    if path:sub(-1, -1) == '/' then
      path = path:sub(1, -2)
    end
    local csrftoken = generate_random_hex_string(16)
    ngx_header['set-cookie'] = ('%s=%s; Path=%s%s; HttpOnly; SameSite=Strict'):format(
      CSRFTOKEN_FIELD_NAME, csrftoken, url_path_prefix, path)
    local enctype
    if upload_type == 'url' then
      enctype = 'application/x-www-form-urlencoded'
    else
      enctype = 'multipart/form-data'
    end
    render('web/upload.html', {
      upload_type = upload_type,
      enctype = enctype,
      csrftoken = csrftoken,
      csrftoken_field = CSRFTOKEN_FIELD_NAME,
      content_field = upload_type,
    })
  end,

  POST = function(upload_type)
    local headers = ngx_req_get_headers()
    local app_id = headers['app-id']
    local direct_upload_json = false
    local direct_upload_plain = false
    if enable_upload_api and app_id then
      log('app_id: %s', app_id)
      local accept_header = headers['accept']
      if type(accept_header) == 'table' then
        accept_header = accept_header[1]
      end
      local accept
      if accept_header then
        accept = parse_accept_header(accept_header):negotiate(MEDIA_TYPES)
      end
      if accept == 'application/json' then
        direct_upload_json = true
        ngx_header['content-type'] = 'application/json'
      else
        direct_upload_plain = true
        ngx_header['content-type'] = 'text/plain'
      end
    end

    local uploader_type
    if direct_upload_json or direct_upload_plain then
      if upload_type == 'url' then
        uploader_type = file_direct_uploader
      else
        uploader_type = url_direct_uploader
      end
    else
      if upload_type == 'url' then
        uploader_type = url_form_uploader
      else
        uploader_type = file_form_uploader
      end
    end

    local uploader, err_code, err = uploader_type:new(upload_type, tg_upload_chat_id, headers)
    if not uploader then
      log(err_code_to_log_level(err_code), 'uploader.new() error: %s: %s', err_code, err)
      return error(err_code, err)
    end
    local file_object
    file_object, err_code, err = uploader:run()
    uploader:close()
    if not file_object then
      log(err_code_to_log_level(err_code), 'uploader.run() error: %s: %s', err_code, err)
      return error(err_code, err)
    end
    local file_size = file_object.file_size
    local bytes_uploaded = uploader.bytes_uploaded
    if file_size and file_size ~= bytes_uploaded then
      log(ngx_WARN, 'size mismatch: file_size: %d, bytes uploaded: %d',
          file_size, bytes_uploaded)
    else
      log('bytes uploaded: %s', bytes_uploaded)
    end
    if uploader:is_max_file_size_exceeded(file_size or bytes_uploaded) then
      log('file is too big for getFile API method, return error to client')
      return error(413, 'the file is too big')
    end

    local media_type_id, media_type = get_media_type_id(uploader.media_type)
    log('tinyid media type: %s (%s)', media_type, media_type_id)

    local tiny_id
    tiny_id, err = tinyid.encode{
      file_id = file_object.file_id,
      media_type_id = media_type_id,
    }
    if not tiny_id then
      log(ngx_ERR, 'failed to encode tiny_id: %s', err)
      return error(ngx_HTTP_INTERNAL_SERVER_ERROR)
    end
    log('tiny_id: %s', tiny_id)

    local render_link = render_link_factory(tiny_id)
    if direct_upload_json then
      ngx_print(json_encode{
        id = tiny_id,
        file_size = file_size,
        media_type = media_type,
        links = {
          inline = render_link('il'),
          download = render_link('dl'),
          links_page = render_link('ln'),
        },
      })
    elseif direct_upload_plain then
      ngx_say(render_link('il'))
    else
      return ngx_redirect(render_link('ln'), ngx_HTTP_SEE_OTHER)
    end
  end

}
