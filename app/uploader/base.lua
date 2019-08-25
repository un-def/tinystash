local tg = require('app.tg')
local utils = require('app.utils')

local prepare_connection = tg.prepare_connection
local request_tg_server = tg.request_tg_server
local get_file_from_message = tg.get_file_from_message

local log = utils.log
local format_error = utils.format_error
local normalize_media_type = utils.normalize_media_type


local not_implemented = function()
  error('not implemented')
end


local _M = {}

_M.__index = _M

_M.new = function()
  not_implemented()
end

_M.run = function()
  not_implemented()
end

_M.upload = function(self, upload_body_iterator)
  -- upload_body_iterator: iterator function producing body chunks
  -- returns:
  --  if ok: table -- TG API object (Document/Video/...) table
  --  if error: nil, err
  -- sets:
  --  self.conn: http connection
  --  self.bytes_uploaded: int (via upload_body_iterator)
  local conn, res, err
  conn, err = prepare_connection()
  if not conn then
    return nil, err
  end
  self.conn = conn
  local params = {
    path = '/bot%s/sendDocument',
    method = 'POST',
    headers = {
      ['content-type'] = 'multipart/form-data; boundary=' .. self.boundary,
      ['transfer-encoding'] = 'chunked',
    },
    body = upload_body_iterator,
  }
  res, err = request_tg_server(conn, params, true)
  if not res then
    return nil, format_error('tg api request error', err)
  end
  if not res.ok then
    return nil, format_error('tg api response is not "ok"', res.description)
  end
  if not res.result then
    return nil, 'tg api response has no "result"'
  end
  local file
  file, err = get_file_from_message(res.result)
  if not file then
    return nil, err
  end
  local file_object = file.object
  if not file_object.file_id then
    return nil, 'tg api response has no file_id'
  end
  return file_object
end

_M.close = function(self)
  if self.conn then
    self.conn:set_keepalive()
  end
end

_M.set_media_type = function(self, media_type)
  -- media_type: string or nil
  -- sets:
  --  self.media_type
  if self.upload_type == 'text' then
    media_type = 'text/plain'
  elseif not media_type then
    media_type = 'application/octet-stream'
  else
    media_type = normalize_media_type(media_type)
  end
  log('media type: %s', media_type)
  self.media_type = media_type
end

return _M
