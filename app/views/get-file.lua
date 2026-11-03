local tinyid = require('app.tinyid')
local utils = require('app.utils')
local constants = require('app.constants')
local helpers = require('app.views.helpers')
local DEFAULT_MEDIA_TYPE = require('app.mediatypes').DEFAULT_TYPE
local cache_status_header = require('app.config')._processed.cache_status_header

local ngx_var = ngx.var
local ngx_exec = ngx.exec
local ngx_header = ngx.header
local ngx_location_capture = ngx.location.capture
local ngx_INFO = ngx.INFO
local ngx_HTTP_HEAD = ngx.HTTP_HEAD
local ngx_HTTP_OK = ngx.HTTP_OK
local ngx_HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND
local ngx_HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY

local log = utils.log
local error = utils.error
local unescape_uri = utils.unescape_uri
local parse_media_type = utils.parse_media_type
local format_file_size = utils.format_file_size
local split_ext = utils.split_ext

local render_link_factory = helpers.render_link_factory
local render = helpers.render

local GET_FILE_MODES = constants.GET_FILE_MODES


local get_file_url = '/_internal/file'


return {

  GET = function(tiny_id, mode, file_name, file_ext)
    local tiny_id_params, tiny_id_err = tinyid.decode(tiny_id)
    if not tiny_id_params then
      log(ngx_INFO, 'tiny_id decode error: %s', tiny_id_err)
      return error(ngx_HTTP_NOT_FOUND)
    end

    if file_name and #file_name == 0 then
      file_name = nil
    end
    if file_ext and #file_ext == 0 then
      file_ext = nil
    end

    local media_type = tiny_id_params.media_type or DEFAULT_MEDIA_TYPE

    if mode == GET_FILE_MODES.LINKS then
      local res = ngx_location_capture(get_file_url, {
        method = ngx_HTTP_HEAD,
        args = {
          file_id = tiny_id_params.file_id,
          media_type = media_type,
          file_name = tiny_id,
          add_ext = true,
        },
      })
      if res.status ~= ngx_HTTP_OK then
        return error(ngx_HTTP_BAD_GATEWAY)
      end

      -- /ln/<tiny-id>.<ext> triggers MIME type autodetection (see the `types` directive)
      -- We need it for static files, so, we set Content-Type explicitly here
      -- rather than disabling autodetection with `types {}`
      -- note, other html handlers rely on `default_type text/html` directive
      ngx_header['Content-Type'] = 'text/html'
      -- copy the cache status header from the response; INLINE/DOWNLOAD modes
      -- pass it by default (`ngx.exec`)
      -- note, nginx.conf uses `more_set_headers`, not `add_header`, which doesn't work
      -- with subrequests (`ngx.location.capture`)
      ngx_header[cache_status_header] = res.header[cache_status_header]

      local file_size = tonumber(res.header['Content-Length']) or -1
      local extension, _
      if file_ext then
        extension = file_ext
      elseif file_name then
        _, extension = split_ext(file_name)
      else
        _, extension = split_ext(res.header['Content-Disposition'] or '')
      end

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

    local add_ext = false
    if not file_name then
      file_name = tiny_id
      if file_ext then
        file_name = file_name .. file_ext
      else
        add_ext = true
      end
    end

    local custom_media_type = ngx_var.arg_mt
    if custom_media_type and #custom_media_type > 0 then
      custom_media_type = unescape_uri(custom_media_type)
      local _, err = parse_media_type(custom_media_type)
      if err then
        log(ngx_INFO, 'invalid custom media type: %s: %s', custom_media_type, err)
      else
        media_type = custom_media_type
      end
    end

    return ngx_exec(get_file_url, {
      file_id = tiny_id_params.file_id,
      media_type = media_type,
      file_name = file_name,
      add_ext = add_ext,
      inline = mode == GET_FILE_MODES.INLINE,
    })

  end

}
