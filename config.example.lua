return {

  aes = {
    key = 'change_me',
    salt = 'change_me_too',
    size = 256,
    mode = 'cbc',
    hash = 'sha512',
    hash_rounds = 5,
  },

  tg_token = 'bot_token',
  tg_webhook_secret = nil,

  link_url_prefix = 'https://example.com',

}
