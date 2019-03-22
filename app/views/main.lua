local template = require('resty.template')

local config = require('config.app')


local tg_bot_username = config.tg.bot_username


return {

  GET = function()
    ngx.header['Content-Type'] = 'text/html'
    template.render('web/main.html', {
      bot_username = tg_bot_username,
    })
  end

}
