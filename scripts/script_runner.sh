#!/bin/sh

# inspired by resty-cli -- https://github.com/openresty/resty-cli

TINYSTASH_DIR=$(dirname $(dirname $(readlink -f "$0")))
SCRIPT_NAME=$(basename "$0")

TEMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TEMP_DIR"
}

trap cleanup EXIT INT QUIT


mkdir "$TEMP_DIR/logs"
CONF="$TEMP_DIR/nginx.conf"

make_arg() {
  echo "arg = {"
  while [ $# -ne 0 ]
  do
    echo "      [===[$1]===],"
    shift
  done
  echo "    }"
}

cat > "$CONF" << __EOF__
daemon off;
master_process off;
worker_processes 1;
pid logs/nginx.pid;
error_log stderr warn;
events {
  worker_connections 64;
}
http {
  access_log off;
  resolver 8.8.8.8 ipv6=off;
  lua_package_path "$TINYSTASH_DIR/?.lua;$TINYSTASH_DIR/resty_modules/lualib/?.lua;;";
  lua_package_cpath "$TINYSTASH_DIR/resty_modules/lualib/?.so;;";
  init_worker_by_lua_block {
    $(make_arg "$@")
    print = function(...)
      io.stdout:write(table.concat({...}))
      io.stdout:write('\n')
      io.stdout:flush()
    end
    ngx.timer.at(0, function()
      local chunk, ok, err
      chunk, err = loadfile('$TINYSTASH_DIR/scripts/$SCRIPT_NAME.lua')
      if not chunk then
        print(err)
        os.exit(1)
      end
      ok, err = pcall(chunk)
      if not ok then
        print(err)
        os.exit(2)
      end
      require('ngx.process').signal_graceful_exit()
    end)
  }
}
__EOF__

/usr/local/openresty/nginx/sbin/nginx -c "$CONF" -p "$TEMP_DIR"
