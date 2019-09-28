#!/bin/sh
tinystash_dir="$(dirname "$(readlink -f "${0}")")"
scripts_dir="${tinystash_dir}/scripts"
resty_runner="${scripts_dir}/resty-runner.sh"

usage() {
  echo "Usage: ${0} COMMAND [COMMAND_ARGS ...]" >&2
  exit 1
}

exec_resty_cmd() {
  exec "${resty_runner}" "${@}"
}

if [ "${#}" -eq 0 ] || [ "${1}" = '-h' ]; then
  usage
fi

command=${1}
shift

case "${command}" in
  webhook)
    exec_resty_cmd webhook "${@}"
    ;;
  run)
    exec /usr/local/openresty/nginx/sbin/nginx -c "${tinystash_dir}/config/nginx.conf" -p "${tinystash_dir}"
    ;;
  *)
    usage
esac
