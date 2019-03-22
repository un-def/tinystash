local tg_bot_username = require('config.app').tg.bot_username


return {

  GET = {'web/main.html', {
    bot_username = tg_bot_username,
  }}

}
