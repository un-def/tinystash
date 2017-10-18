return {

  aes = {
    key = 'change_me',
    salt = 'changeme',   -- salt can be either nil or exactly 8 characters long
    size = 256,
    mode = 'cbc',
    hash = 'sha512',
    hash_rounds = 5,
  },

  tg = {
    bot_username = 'tinystash_bot',
    token = 'bot_token',
    webhook_secret = nil,
  },

  link_url_prefix = 'https://example.com',
  hide_image_download_link = false,

}
