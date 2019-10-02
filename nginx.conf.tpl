daemon off;
worker_processes {* worker_processes *};
pid nginx.pid;

{% for _, line in ipairs(error_log) do %}
error_log {* line *};
{% end %}

events {
  worker_connections {* worker_connections *};
}

env TINYSTASH_CONFIG_PATH;

http {
  server_tokens off;

  resolver {* resolver *};
  lua_ssl_trusted_certificate {* lua_ssl_trusted_certificate *};
  lua_ssl_verify_depth {* lua_ssl_verify_depth *};

  lua_package_path "$prefix/resty_modules/lualib/?.lua;$prefix/resty_modules/lualib/?/init.lua;$prefix/?.lua;$prefix/?/init.lua;;";
  lua_package_cpath "$prefix/resty_modules/lualib/?.so;;";

  init_by_lua_block {
    require('resty.core')
    {% if resty_http_debug_logging then %}
    require('resty.http').debug(true)
    {% end %}
    collectgarbage('collect')
  }

  server {
    listen {* listen *};
    access_log {* access_log *};
    lua_code_cache {* lua_code_cache *};
    default_type text/html;
    client_max_body_size {* client_max_body_size *};
    error_page 400 403 404 405 411 413 500 501 502 /error;
    set $template_root templates;

    location = / {
      content_by_lua_block {
        require('app.views').main()
      }
    }

    location /static/ {
      alias ./static/;
      try_files $uri =404;
      include /usr/local/openresty/nginx/conf/mime.types;
    }

    location ~ ^/docs/api/?$ {
      content_by_lua_block {
        require('app.views').docs_api()
      }
    }

    location ~ ^/(?P<mode>dl|il|ln)/(?P<tiny_id>[a-zA-Z0-9]+)(?:\.[a-zA-Z0-9]+|/(?P<file_name>[^\\/]+))?/?$ {
      content_by_lua_block {
        require('app.views').get_file(ngx.var.tiny_id, ngx.var.mode, ngx.var.file_name)
      }
    }

    location ~ ^/webhook/(?P<secret>[a-zA-Z0-9:_-]+)/?$ {
      content_by_lua_block {
        require('app.views').webhook(ngx.var.secret)
      }
    }

    location ~ ^/upload(?:/(?P<type>text|file))?/?$ {
      content_by_lua_block {
        require('app.views').upload(ngx.var.type)
      }
    }

    location / {
      return 404;
    }

    location /error {
      internal;
      # This redundant declaration is needed for some reason.
      # Try to execute `GET /` with `content-length:-1` without this line:
      # > [info] ... client sent invalid "Content-Length" header while reading client request headers
      # > [warn] ... using uninitialized "template_root" variable while reading client request headers
      set $template_root templates;
      content_by_lua_block {
        require('app.views').error()
      }
    }

  }

}
