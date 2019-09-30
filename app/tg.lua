local http = require('resty.http')
local json = require('cjson.safe')

local constants = require('app.constants')
local config = require('app.config')

local TG_API_HOST = constants.TG_API_HOST
local TG_TYPES = constants.TG_TYPES
local TG_TYPE_PHOTO = TG_TYPES.PHOTO
local tg_token = config.tg.token
local tg_request_timeout_ms = config.tg.request_timeout * 1000


local _M = {}

_M.prepare_connection = function()
  local conn, err = http.new()
  if not conn then
    return nil, err
  end
  conn:set_timeout(tg_request_timeout_ms)
  return conn
end

_M.request_tg_server = function(conn, params, decode_json)
  -- params table mutation!
  params.path = params.path:format(tg_token)
  local res, err
  res, err = conn:connect(TG_API_HOST, 443)
  if not res then return nil, err end
  res, err = conn:ssl_handshake(nil, TG_API_HOST, true)
  if not res then return nil, err end
  res, err = conn:request(params)
  if not res then return nil, err end
  -- don't forget to call :close or :set_keepalive
  if not decode_json then return res end
  local body
  body, err = res:read_body()
  conn:set_keepalive()
  if not body then return nil, err end
  return json.decode(body)
end

_M.get_file_from_message = function(message)
  -- message: TG bot API Message object
  -- returns:
  --   if ok: table with keys 'object' and 'type'
  --          where 'object' is one of TG bot API objects (Document/Video/...)
  --          and 'type' is one of TG_TYPES constants
  --   if no file found: nil, err
  local file_obj, file_obj_type
  for _, _file_obj_type in pairs(TG_TYPES) do
    file_obj = message[_file_obj_type]
    if file_obj then
      file_obj_type = _file_obj_type
      if file_obj_type == TG_TYPE_PHOTO then
        file_obj = file_obj[#file_obj]
      end
      return {
        object = file_obj,
        type = file_obj_type,
      }
    end
  end
  return nil, 'no file in the message'
end

return _M
