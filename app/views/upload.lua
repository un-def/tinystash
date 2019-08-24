local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local helpers = require('app.views.helpers')
local uploader = require('app.uploader')

local tg_upload_chat_id = require('config.app').tg.upload_chat_id


local ngx_redirect = ngx.redirect
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_HTTP_SEE_OTHER = ngx.HTTP_SEE_OTHER
local ngx_HTTP_FORBIDDEN = ngx.HTTP_FORBIDDEN
local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND
local ngx_HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local ngx_HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR

local log = utils.log
local exit = utils.exit
local generate_random_hex_string = utils.generate_random_hex_string
local parse_media_type = utils.parse_media_type
local get_media_type_id = utils.get_media_type_id
local render_link_factory = helpers.render_link_factory
local render = helpers.render

local TG_MAX_FILE_SIZE = constants.TG_MAX_FILE_SIZE

local FIELD_NAME_CSRFTOKEN = uploader.FIELD_NAME_CSRFTOKEN


return {

  initial = function(upload_type)
    if not tg_upload_chat_id then
      exit(ngx_HTTP_NOT_FOUND)
    end
    if upload_type == '' then
      upload_type = 'file'
    end
    return upload_type
  end,

  GET = function(upload_type)
    local csrftoken = generate_random_hex_string(16)
    ngx.header['set-cookie'] = (
      '%s=%s; Path=/; HttpOnly; SameSite=Strict'):format(FIELD_NAME_CSRFTOKEN, csrftoken)
    render('web/upload.html', {
      upload_type = upload_type,
      csrftoken_name = FIELD_NAME_CSRFTOKEN,
      csrftoken_value = csrftoken,
    })
  end,

  POST = function(upload_type)
    local headers = ngx.req.get_headers()
    local app_id = headers['app-id']
    local csrftoken
    if app_id then
      log('app_id: %s', app_id)
    else
      local cookie = headers['cookie']
      if not cookie then
        log('no cookie header')
        exit(ngx_HTTP_FORBIDDEN)
      end
      for key, value in cookie:gmatch('([^%c%s;]+)=([^%c%s;]+)') do
        if key == FIELD_NAME_CSRFTOKEN then
          csrftoken = value
          break
        end
      end
      if not csrftoken then
        log('no csrftoken cookie')
        exit(ngx_HTTP_FORBIDDEN)
      end
    end

    local upldr, err = uploader:new(upload_type, tg_upload_chat_id, csrftoken)
    if not upldr then
      log('failed to init uploader: %s', err)
      exit(ngx_HTTP_BAD_REQUEST)
    end
    local file_object, err_code
    file_object, err_code, err = upldr:run()
    upldr:close()

    if not file_object then
      local loglevel = err_code >= 500 and ngx_ERR or ngx_DEBUG
      log(loglevel, err)
      exit(err_code)
    end
    local file_size = file_object.file_size
    local bytes_uploaded = upldr.bytes_uploaded
    if file_size and file_size ~= bytes_uploaded then
      log(ngx_WARN, 'size mismatch: file_size: %d, bytes uploaded: %d',
          file_size, bytes_uploaded)
    else
      log('bytes uploaded: %s', bytes_uploaded)
    end
    if (file_size or bytes_uploaded) > TG_MAX_FILE_SIZE then
      log('file is too big for getFile API method, return error to client')
      exit(413)
    end

    local media_type = upldr.media_type
    local media_type_id = get_media_type_id(media_type)
    if not media_type_id then
      local media_type_table = parse_media_type(media_type)
      if media_type_table[1] == 'text' then
        media_type_id = get_media_type_id('text/plain')
      end
    end

    local tiny_id
    tiny_id, err = tinyid.encode{
      file_id = file_object.file_id,
      media_type_id = media_type_id,
    }
    if not tiny_id then
      log(ngx_ERR, 'failed to encode tiny_id: %s', err)
      exit(ngx_HTTP_INTERNAL_SERVER_ERROR)
    end
    ngx_redirect(render_link_factory(tiny_id)('ln'), ngx_HTTP_SEE_OTHER)
  end

}
