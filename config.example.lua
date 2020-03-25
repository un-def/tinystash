return {

  aes = {
    key = 'change_me',
    -- salt can be either nil or exactly 8 characters long
    salt = 'changeme',
    size = 256,
    mode = 'cbc',
    hash = 'sha512',
    hash_rounds = 5,
  },

  tg = {
    bot_username = 'tinystash_bot',
    -- bot authorization token
    token = 'bot_token',
    -- tg server request timeout, seconds
    request_timeout = 10,
    -- secret part of the webhook url: https://www.example.com/webhook/<secret>
    -- set to nil to use the authorization token as a secret
    -- see also: https://core.telegram.org/bots/api#setwebhook
    webhook_secret = nil,
    -- chat_id (integer or string) for uploaded files
    -- set to nil to disable http uploading
    upload_chat_id = nil,
  },

  nginx_conf = {
    -- (int, required)
    listen = 80,
    -- (int, required)
    worker_processes = 4,
    -- (int, required)
    worker_connections = 1024,
    -- (string, required) 20 MiB getFile API method limit + 10% (multipart/form-data overhead)
    client_max_body_size = '22M',
    -- (array of strings, optional)
    error_log = {
      -- log everything to stderr
      'stderr debug',
      -- uncomment the next line to log error messages to a file
      -- 'logs/error.log error',
    },
    -- (string, optional, default is 'off') access log is disabled, set file path to enable
    access_log = 'off',
    -- (string, required)
    resolver = '8.8.8.8 ipv6=off',
    -- ('on' | 'off', optional, default is 'on') set to 'off' in development mode
    lua_code_cache = 'on',
    -- (string, required)
    lua_ssl_trusted_certificate = '/etc/ssl/certs/ca-certificates.crt',
    -- (int, required)
    lua_ssl_verify_depth = 5,
    -- (boolean, optional, default is false)
    resty_http_debug_logging = false,
  },

  -- url prefix for generated links: scheme://host[:port][/path], e.g.,
  -- https://example.com/         -->   https://example.com/ln/<tiny_id>
  -- https://example.com/tiny     -->   https://example.com/tiny/ln/<tiny_id>
  -- https://example.com/stash/   -->   https://example.com/stash/ln/<tiny_id>
  -- trailing slashes are ignored
  link_url_prefix = 'https://example.com/',
  -- don't show download links in bot response if content-type is image/*
  hide_image_download_link = false,
  -- enable direct file upload (e.g., via curl)
  enable_upload_api = true,

  -- Google Tag Manager ID (Container ID), string or nil
  gtm_id = nil,

}
