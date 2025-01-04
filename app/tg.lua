local http = require('resty.http')
local json = require('cjson.safe')

local constants = require('app.constants')
local config = require('app.config')
local utils = require('app.utils')

local tostring = tostring
local string_find = string.find
local string_lower = string.lower
local string_format = string.format
local json_encode = json.encode
local json_decode = json.decode

local TG_API_HOST = constants.TG_API_HOST
local TG_TYPES = constants.TG_TYPES
local TG_TYPE_PHOTO = TG_TYPES.PHOTO
local wrap_error = utils.wrap_error
local escape_uri = utils.escape_uri
local set = utils.set


local _TG_TOKEN = config.tg.token
local _REQUEST_TIMEOUT_MS = config.tg.request_timeout * 1000
local _CONNECTION_OPTIONS = {
  scheme = 'https',
  host = TG_API_HOST,
}
local _EXPECTED_200 = set{200}
local _EXPECTED_200_201 = set{200, 201}
local _EXPECTED_200_304 = set{200, 304}
local _EXPECTED_200_201_400 = set{200, 201, 400}


local client_mt = {}

client_mt.__index = client_mt

client_mt.send_message = function(self, json_body)
  local options = {
    method = 'POST',
    json = json_body,
  }
  return self:_call_api('sendMessage', options, _EXPECTED_200_201)
end

client_mt.send_document = function(self, json_body_or_options)
  local options
  if json_body_or_options.chat_id then
    options = {
      method = 'POST',
      json = json_body_or_options,
    }
  else
    options = json_body_or_options
    if not options.method then
      options.method = 'POST'
    end
  end
  -- 400 is expected status for url uploads
  return self:_call_api('sendDocument', options, _EXPECTED_200_201_400)
end

client_mt.forward_message = function(self, json_body)
  local options = {
    method = 'POST',
    json = json_body,
  }
  return self:_call_api('forwardMessage', options, _EXPECTED_200_201)
end

client_mt.get_file = function(self, file_id)
  local options = {
    method = 'GET',
    query = {file_id = file_id},
  }
  return self:_call_api('getFile', options, _EXPECTED_200)
end

client_mt.request_file = function(self, file_path, etag)
  local expected
  local headers
  if etag then
    headers = {
      ['If-None-Match'] = etag,
    }
    expected = _EXPECTED_200_304
  else
    expected = _EXPECTED_200
  end
  local params = {
    method = 'GET',
    path = string_format('/file/bot%s/%s', _TG_TOKEN, escape_uri(file_path)),
    headers = headers,
  }
  return self:_request(params, expected)
end

client_mt.close = function(self)
  local conn = self._conn
  if conn then
    conn:set_keepalive()
    self._conn = nil
  end
end

client_mt._call_api = function(self, api_method, options, expected)
  -- options: table:
  --    method: str HTTP method
  --    headers: table | nil
  --    query: table | nil
  --    decode: boolean -- decode JSON response, default = true
  --    body: iterator function
  --      or
  --    json: table -- JSON boby
  -- expected: utils.set table | nil
  -- returns:
  --    resp_or_json_body | nil, err | nil
  local headers = {}
  local body = options.body
  local json_body = options.json
  if json_body then
    body = json_encode(json_body)
    headers['Content-Type'] = 'application/json'
    headers['Content-Length'] = #body
  end
  local opt_headers = options.headers
  if opt_headers then
    for header, value in pairs(opt_headers) do
      headers[header] = value
    end
  end
  local params = {
    method = options.method,
    path = string_format('/bot%s/%s', _TG_TOKEN, api_method),
    headers = headers,
    query = options.query,
    body = body,
  }
  local resp, err = self:_request(params, expected)
  if err then
    return resp, wrap_error('resty.http request error', err)
  end
  local decode = options.decode
  if decode == nil then
    decode = true
  end
  if not decode then
    return resp
  end
  local resp_body
  resp_body, err = resp:read_body()
  if not resp_body then
    return resp, wrap_error('resty.http read_body error', err)
  end
  if resp_body == '' then
    return resp, string_format('%d: empty response body', resp.status)
  end
  local resp_json
  resp_json, err = json_decode(resp_body)
  if not resp_json then
    return resp, wrap_error('response decode error', err)
  end
  return resp_json
end

client_mt._request = function(self, params, expected)
  local conn, err = self:_connect()
  if not conn then
    return nil, err
  end
  local resp
  resp, err = conn:request(params)
  if not resp then
    return nil, wrap_error('resty.http request error', err)
  end
  if expected then
    local status = resp.status
    if not expected[status] then
      return resp, string_format('unexpected tg response status: %d', status)
    end
  end
  return resp
end

client_mt._connect = function(self)
  local conn, err = self:_get_connection()
  if not conn then
    return nil, err
  end
  local ok
  ok, err = conn:connect(_CONNECTION_OPTIONS)
  if not ok then
    return nil, wrap_error('resty.http connect error', err)
  end
  return conn
end

client_mt._get_connection = function(self)
  local conn = self._conn
  if conn then
    return conn
  end
  local err
  conn, err = http.new()
  if not conn then
    return nil, wrap_error('resty.http new error', err)
  end
  conn:set_timeout(_REQUEST_TIMEOUT_MS)
  self._conn = conn
  return conn
end

local _M = {}

_M.client = function()
  return setmetatable({}, client_mt)
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

local URL_UPLOAD_ERROR_FAILED = 'FAILED'
local URL_UPLOAD_ERROR_FAILED_PATTERN = string_lower('failed to get HTTP URL content')
local URL_UPLOAD_ERROR_REJECTED = 'REJECTED'
local URL_UPLOAD_ERROR_REJECTED_PATTERN = string_lower('wrong file identifier/HTTP URL specified')

_M.URL_UPLOAD_ERROR_FAILED = URL_UPLOAD_ERROR_FAILED
_M.URL_UPLOAD_ERROR_REJECTED = URL_UPLOAD_ERROR_REJECTED

_M.get_url_upload_error_type = function(err)
  local err_lower = string_lower(tostring(err))
  if string_find(err_lower, URL_UPLOAD_ERROR_FAILED_PATTERN, 1, true) then
    return URL_UPLOAD_ERROR_FAILED
  end
  if string_find(err_lower, URL_UPLOAD_ERROR_REJECTED_PATTERN, 1, true) then
    return URL_UPLOAD_ERROR_REJECTED
  end
  return nil
end

return _M
