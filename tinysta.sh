#!/bin/sh

OPENRESTY_PREFIX=${OPENRESTY_PREFIX:-/usr/local/openresty}
export OPENRESTY_PREFIX
TINYSTASH_DIR=$(dirname "$(readlink -f "${0}")")
export TINYSTASH_DIR
TINYSTASH_CONFIG_PATH=$(readlink -f "${TINYSTASH_CONFIG_PATH:-"${TINYSTASH_DIR}/config.lua"}")
export TINYSTASH_CONFIG_PATH

command_runner="${TINYSTASH_DIR}/commands/command-runner.sh"
nginx_conf="${TINYSTASH_DIR}/nginx.conf"

usage() {
  echo "
usage: ${0} COMMAND [ARGS]

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
    exec "${command_runner}" "${command}" "${@}"
    ;;
  run)
    echo "using config: ${TINYSTASH_CONFIG_PATH}"
    echo
    if ! nginx_conf_content=$("${command_runner}" conf); then
      echo "error while generating nginx.conf:"
      echo "${nginx_conf_content}"
      exit 2
    fi
    echo "${nginx_conf_content}" > "${nginx_conf}"
    exec "${OPENRESTY_PREFIX}/nginx/sbin/nginx" -c "${nginx_conf}" -p "${TINYSTASH_DIR}"
    ;;
  *)
    usage
esac
