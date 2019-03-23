local http = require('resty.http')
local json = require('cjson.safe')

local constants = require('app.constants')
local config = require('config.app')

local TG_API_HOST = constants.TG_API_HOST
local tg_token = config.tg.token
local tg_request_timeout = config.tg.request_timeout * 1000


local _M = {}

_M.prepare_connection = function()
  local conn, err = http.new()
  if not conn then
    return nil, err
  end
  conn:set_timeout(tg_request_timeout)
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

return _M
