#!/bin/sh

# inspired by resty-cli -- https://github.com/openresty/resty-cli

die() {
  test ${#} -ne 0 && echo "${@}"
  exit 1
}

check_is_set() {
  test -n "${2}" && return
  die "${1} is not set"
}

check_is_set OPENRESTY_PREFIX "${OPENRESTY_PREFIX}"
check_is_set TINYSTASH_DIR "${TINYSTASH_DIR}"
test ${#} -ge 1 || die "usage: ${0} COMMAND [ARGS]"

COMMANDS_DIR="${COMMANDS_DIR:-"${TINYSTASH_DIR}/commands"}"
command_name=${1}
shift

nginx_root=$(mktemp -d)

cleanup() {
  rm -rf "${nginx_root}"
  trap - EXIT
}

trap cleanup EXIT INT QUIT TERM HUP

mkdir "${nginx_root}/logs"
nginx_conf="${nginx_root}/nginx.conf"

make_argv() {
  echo "local argv = {"
  while [ ${#} -ne 0 ]
  do
    echo "      [===[${1}]===],"
    shift
  done
  echo "    }"
}

cat > "${nginx_conf}" << __EOF__
daemon off;
master_process off;
worker_processes 1;
pid logs/nginx.pid;
env TINYSTASH_CONFIG_PATH;
error_log stderr warn;
events {
  worker_connections 64;
}
http {
  access_log off;
  resolver 8.8.8.8 ipv6=off;
  lua_package_path "${TINYSTASH_DIR}/?.lua;${TINYSTASH_DIR}/resty_modules/lualib/?.lua;;";
  lua_package_cpath "${TINYSTASH_DIR}/resty_modules/lualib/?.so;;";
  init_worker_by_lua_block {
    _G.OPENRESTY_PREFIX = [===[${OPENRESTY_PREFIX}]===]
    local TINYSTASH_DIR = [===[${TINYSTASH_DIR}]===]
    _G.TINYSTASH_DIR = TINYSTASH_DIR
    _G.print = function(...)
      io.stdout:write(table.concat({...}))
      io.stdout:write('\n')
      io.stdout:flush()
    end
    local orig_error = error
    _G.error = function(msg, lvl)
      orig_error(msg, lvl or 0)
    end
    _G.run_command = function(command_name, argv)
      local chunk, err = loadfile([===[${COMMANDS_DIR}]===] .. '/' .. command_name .. '.lua')
      if not chunk then
        return false, err
      end
      local ok, err = pcall(chunk, argv)
      if not ok then
        return false, err
      end
      return true
    end
    require('ngx.process').signal_graceful_exit()
    ngx.timer.at(0, function()
      local command_name = [===[${command_name}]===]
      $(make_argv "${@}")
      local ok, err = run_command(command_name, argv)
      if not ok then
        print(err)
        os.exit(1)
      end
    end)
  }
}
__EOF__

"${OPENRESTY_PREFIX}/nginx/sbin/nginx" -c "${nginx_conf}" -p "${nginx_root}"
