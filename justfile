project = 'tinystash'

_list:
  @just --list

sudo +args:
  @sudo --preserve-env=PATH env just {{args}}

run:
  /usr/local/openresty/nginx/sbin/nginx -c config/nginx.conf -p .
