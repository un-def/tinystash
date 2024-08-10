project := 'tinystash'

_list:
  @just --list --unsorted

install-deps:
  opm --cwd get $(cat requirements.opm)

lint:
  luacheck .

run:
  ./tinysta.sh run

build:
  docker build . \
    --pull --no-cache \
    --tag "{{project}}:$(date '+%y%m%d%H%M')" --tag "{{project}}:latest"
