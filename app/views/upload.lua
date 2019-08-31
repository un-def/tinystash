local json = require('cjson.safe')

local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local helpers = require('app.views.helpers')
local formdata_uploader = require('app.uploader.formdata')
local raw_uploader = require('app.uploader.raw')

local tg_upload_chat_id = require('config.app').tg.upload_chat_id


local ngx_redirect = ngx.redirect
local ngx_print = ngx.print
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_HTTP_SEE_OTHER = ngx.HTTP_SEE_OTHER
local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND
local ngx_HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR

local log = utils.log
local exit = utils.exit
local generate_random_hex_string = utils.generate_random_hex_string
local parse_media_type = utils.parse_media_type
local get_media_type_id = utils.get_media_type_id
local render_link_factory = helpers.render_link_factory
local render = helpers.render

local TG_MAX_FILE_SIZE = constants.TG_MAX_FILE_SIZE

local FIELD_NAME_CONTENT = formdata_uploader.FIELD_NAME_CONTENT
local FIELD_NAME_CSRFTOKEN = formdata_uploader.FIELD_NAME_CSRFTOKEN


local err_code_to_log_level = function(err_code)
  if err_code >= 500 then
    return ngx_ERR
  end
  return ngx_DEBUG
end


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
      content_name = FIELD_NAME_CONTENT,
    })
  end,

  POST = function(upload_type)
    local headers = ngx.req.get_headers()
    local uploader_type
    local app_id = headers['app-id']
    if app_id then
      log('app_id: %s', app_id)
      uploader_type = raw_uploader
    else
      uploader_type = formdata_uploader
    end
    local uploader, err_code, err = uploader_type:new(upload_type, tg_upload_chat_id, headers)
    if not uploader then
      log(err_code_to_log_level(err_code), 'failed to init uploader: %s', err)
      exit(err_code)
    end
    local file_object
    file_object, err_code, err = uploader:run()
    uploader:close()
    if not file_object then
      log(err_code_to_log_level(err_code), 'failed to upload: %s', err)
      exit(err_code)
    end
    local file_size = file_object.file_size
    local bytes_uploaded = uploader.bytes_uploaded
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

    local media_type = uploader.media_type
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

    local render_link = render_link_factory(tiny_id)
    if app_id then
      if headers['accept'] == 'application/json' then
        ngx.header['content-type'] = 'application/json'
        ngx.print(json.encode{
          file_size = file_size,
          media_type = media_type,
          tiny_id = tiny_id,
          links = {
            inline = render_link('il'),
            download = render_link('dl'),
            links_page = render_link('ln'),
          },
        })
      else
        ngx.header['content-type'] = 'text/plain'
        ngx_print(render_link('dl'))
      end
    else
      ngx_redirect(render_link('ln'), ngx_HTTP_SEE_OTHER)
    end
  end

}
