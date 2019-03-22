local exit = require('app.utils').exit


local view_metatable = {
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
    view_table[method:upper()] = handler
  end
  return setmetatable(view_table, view_metatable)
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
