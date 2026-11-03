daemon off;
worker_processes {* worker_processes *};
pid nginx.pid;
pcre_jit on;

{% for _, line in ipairs(error_log) do %}
error_log {* line *};
{% end %}

events {
  {% if worker_connections then %}
  worker_connections {* worker_connections *};
  {% end %}
}

env TINYSTASH_CONFIG_PATH;

http {
  server_tokens off;
  sendfile on;
  absolute_redirect off;
  resolver {* resolver *};

  lua_code_cache {* lua_code_cache *};
  lua_package_path "$prefix/resty_modules/lualib/?.lua;$prefix/resty_modules/lualib/?/init.lua;$prefix/?.lua;$prefix/?/init.lua;;";
  lua_package_cpath "$prefix/resty_modules/lualib/?.so;;";
  lua_ssl_trusted_certificate {* lua_ssl_trusted_certificate *};
  lua_ssl_verify_depth {* lua_ssl_verify_depth *};

  init_by_lua_block {
    {% if resty_http_debug_logging then %}
    require('resty.http').debug(true)
    {% end %}
    collectgarbage('collect')
  }

  {% if cache_valid then %}
  proxy_cache_path ./file_cache levels=1:2 keys_zone=file_cache:{* cache_zone_size *} inactive={* cache_inactive *} max_size={* cache_max_size *};
  {% end %}

  upstream file_proxy {
      server unix:./file_proxy.sock;
      keepalive 32;
  }

  server {
    listen unix:./file_proxy.sock;
    access_log off;
    default_type application/octet-stream;

    location = /file {
      content_by_lua_block {
        require('app.file-proxy').get_file_handler()
      }
    }

  }

  server {
    listen {* listen *};
    access_log {* access_log *};
    default_type text/html;
    client_max_body_size 8k;
    error_page 400 403 404 405 411 413 500 501 502 /_internal/error;

    location = /_internal/error {
      internal;
      content_by_lua_block {
        require('app.views').error()
      }
    }

    location = /_internal/file {
      internal;
      proxy_pass http://file_proxy/file;
      proxy_intercept_errors on;
      proxy_force_ranges on;
      {% if cache_valid then %}
      proxy_cache file_cache;
      proxy_cache_key $arg_file_id;
      proxy_cache_valid 200 {* cache_valid *};
      proxy_cache_lock on;
      proxy_cache_lock_timeout 10s;
      proxy_cache_lock_age 15s;
      proxy_cache_convert_head on;
      proxy_cache_use_stale updating;
      {% if cache_status_header then %}
      more_set_headers "{* cache_status_header *}: $upstream_cache_status";
      {% end %}
      {% end %}

      header_filter_by_lua_block {
        require('app.file-proxy').get_file_header_filter()
      }

    }

    location /static/ {
      alias ./static/;
      try_files $uri =404;
      include {* OPENRESTY_PREFIX *}/nginx/conf/mime.types;
    }

    location = /favicon.ico {
      alias ./static/favicon.ico;
      default_type image/vnd.microsoft.icon;
    }

    location = / {
      content_by_lua_block {
        require('app.views').main()
      }
    }

    location ~ ^/donate/?$ {
      content_by_lua_block {
        require('app.views').donate()
      }
    }

    location ~ ^/docs/api/?$ {
      content_by_lua_block {
        require('app.views').docs_api()
      }
    }

    location ~ ^/(?P<mode>dl|il|ln)/(?P<tiny_id>[a-zA-Z0-9]+)(?:(?P<file_ext>\.[a-zA-Z0-9_.]+)|/(?P<file_name>[^\\/]+))?/?$ {
      content_by_lua_block {
        require('app.views').get_file(ngx.var.tiny_id, ngx.var.mode, ngx.var.file_name, ngx.var.file_ext)
      }
    }

    location ~ ^/webhook/(?P<secret>[a-zA-Z0-9:_-]+)/?$ {
      client_max_body_size 256k;
      content_by_lua_block {
        require('app.views').webhook(ngx.var.secret)
      }
    }

    location ~ ^/upload/?$ {
      return 308 /upload/file;
    }

    location ~ ^/upload/(?P<type>file|text)/?$ {
      client_max_body_size {* client_max_body_size *};
      content_by_lua_block {
        require('app.views').upload(ngx.var.type)
      }
    }

    location ~ ^/upload/url/?$ {
      client_max_body_size 8k;
      content_by_lua_block {
        require('app.views').upload('url')
      }
    }

    location / {
      return 404;
    }

    header_filter_by_lua_block {
      require('app.phases.header_filter').deny_page_framing()
    }

  }

}
