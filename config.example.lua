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
    -- chat_id (integer or string) for forwarded messages
    -- set to nil to disable message forwarding
    forward_chat_id = nil,
  },

  nginx_conf = {
    -- (int, required)
    listen = 80,
    -- (int | 'auto', optional, default is 'auto')
    worker_processes = 'auto',
    -- (int, optional)
    worker_connections = nil,
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
    -- (boolean | 'on' | 'off', optional, default is true/'on') set to false/'off' in development mode
    lua_code_cache = true,
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

  donate = {
    -- enable donate page
    enable = false,
    -- the intro text displayed before blocks, html-formatted
    -- set to nil to disable
    intro = '<h1>Please donate</h1>',
    -- an array of blocks; each block may contain text, text+link, or html
    blocks = {
      {
        text = 'this is a line of text',
      },
      {
        text = 'this is a link to example.com/donate',
        link = 'https://example.com/donate',
      },
      {
        html = 'this is an <strong>html block</strong>',
      },
    },
  },

  -- Google Tag Manager ID (Container ID), string or nil
  gtm_id = nil,

}
