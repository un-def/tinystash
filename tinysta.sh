#!/bin/sh

tinystash_dir=$(dirname "$(readlink -f "${0}")")
nginx_conf="${tinystash_dir}/nginx.conf"
scripts_dir="${tinystash_dir}/scripts"
resty_runner="${scripts_dir}/resty-runner.sh"

TINYSTASH_CONFIG_PATH=$(readlink -f "${TINYSTASH_CONFIG_PATH:-"${tinystash_dir}/config.lua"}")
export TINYSTASH_CONFIG_PATH

usage() {
  echo "
usage: ${0} COMMAND [COMMAND_ARGS ...]

commands:
  run
  conf
  webhook
"
  exit 1
}

if [ "${#}" -eq 0 ] || [ "${1}" = '-h' ]; then
  usage
fi

command=${1}
shift

case "${command}" in
  conf|webhook)
    echo "using config: ${TINYSTASH_CONFIG_PATH}"
    echo
    exec "${resty_runner}" "${command}" "${@}"
    ;;
  run)
    echo "using config: ${TINYSTASH_CONFIG_PATH}"
    if ! nginx_conf_content=$("${resty_runner}" conf); then
      echo "error while generating nginx.conf:"
      echo "${nginx_conf_content}"
      exit 2
    fi
    echo "${nginx_conf_content}" > "${nginx_conf}"
    exec /usr/local/openresty/nginx/sbin/nginx -c "${nginx_conf}" -p "${tinystash_dir}"
    ;;
  *)
    usage
esac
