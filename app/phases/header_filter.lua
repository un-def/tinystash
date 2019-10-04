local ngx_header = ngx.header


local _M = {}

_M.deny_page_framing = function()
  -- block framing any html page, excluding uploaded files (detected by
  -- the presense of the 'content-disposition' header)
  if not ngx_header['content-disposition'] and ngx_header['content-type'] == 'text/html' then
    -- for modern browsers
    -- https://caniuse.com/#feat=mdn-http_headers_csp_content-security-policy_frame-ancestors
    ngx_header['content-security-policy'] = "frame-ancestors 'none'"
    -- for older browsers
    ngx_header['x-frame-options'] = 'deny'
  end
end

return _M
