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
    -- secret part of the webhook url: https://www.example.com/<secret>
    -- set to nil to use the authorization token as a secret
    -- see also: https://core.telegram.org/bots/api#setwebhook
    webhook_secret = nil,
  },

  -- url prefix for generated links: scheme://host[:port][/path], e.g.,
  -- https://example.com/         -->   https://example.com/ln/<tiny_id>
  -- https://example.com/tiny     -->   https://example.com/tiny/ln/<tiny_id>
  -- https://example.com/stash/   -->   https://example.com/stash/ln/<tiny_id>
  -- trailing slashes are ignored
  link_url_prefix = 'https://example.com/',
  -- don't show download links in bot response if content-type is image/*
  hide_image_download_link = false,

}
