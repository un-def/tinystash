local exit = require('app.utils').exit
local render_to_string = require('app.views.helpers').render_to_string


local template_handler_meta = {
  __call = function(self)
    if self.content then
      ngx.print(self.content)
      return
    end
    local content = render_to_string(self.template, self.context)
    if self.cache then
      self.content = content
    end
    ngx.print(content)
  end
}


local template_handler = function(template_path, context, cache)
  if cache == nil then
    cache = true
  end
  return setmetatable({
    template = template_path,
    context = context,
    cache = cache,
  }, template_handler_meta)
end


local view_meta = {
  __call = function(self, ...)
    local method = ngx.req.get_method()
    local handler = self[method]
    if not handler then
      exit(ngx.HTTP_NOT_ALLOWED)
    else
      handler(...)
    end
  end
}


local view = function(handlers)
  local view_table = {}
  for method, handler in pairs(handlers) do
    if type(handler) == 'table' then
      handler = template_handler(unpack(handler))
    end
    view_table[method:upper()] = handler
  end
  return setmetatable(view_table, view_meta)
end


local viewset = function(views)
  local viewset_table = {}
  for name, view_ in pairs(views) do
    viewset_table[name] = view(view_)
  end
  return viewset_table
end


return viewset{
  main = require('app.views.main'),
  getfile = require('app.views.getfile'),
  webhook = require('app.views.webhook'),
}
