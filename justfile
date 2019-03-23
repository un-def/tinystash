project = 'tinystash'

_list:
  @just --list

sudo +args:
  @sudo --preserve-env=PATH env just {{args}}

install-deps:
  #!/bin/sh
  while read dep; do opm --cwd install "$dep"; done < requirements.opm

run:
  /usr/local/openresty/nginx/sbin/nginx -c config/nginx.conf -p .
