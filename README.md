# ᵗⁱⁿʸ[stash]

[![version](https://img.shields.io/github/tag/un-def/tinystash.svg?maxAge=3600&style=flat-square&label=version)](https://github.com/un-def/tinystash/releases)
[![license](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](https://github.com/un-def/tinystash/blob/master/LICENSE)
[![Docker pulls](https://img.shields.io/docker/pulls/un1def/tinystash.svg?maxAge=3600&style=flat-square)](https://hub.docker.com/r/un1def/tinystash/)

A storage-less, database-less, \_\_\_\_\_\_\_\_-less filesharing. Send anything to [@tinystash_bot][tinystash_bot] [Telegram][telegram] bot. Get an opaque http link. Share it.

Written in [Lua][lua]. Powered by [OpenResty][openresty].


### Installing

#### OpenResty

See [instructions][openresty_installation] on [OpenResty website][openresty].

#### Lua packages

```shell
$ while read dep; do opm --cwd get "$dep"; done < requirements.opm
```


### Configuring

Copy app and nginx configs from examples and edit them:

```shell
$ cp config/app.example.lua config/app.lua
$ cp config/nginx.example.conf config/nginx.conf
```


### Setting up Telegram bot webhook

```shell
$ scripts/webhook set
```


### Running

```shell
$ /usr/local/openresty/nginx/sbin/nginx -c config/nginx.conf -p .
```


### Quick deployment with Docker

1. Prepare `config` directory with `nginx.conf` and `app.lua` configs.

2. Run Docker container:
```shell
$ docker run -d \
    --restart unless-stopped \
    # Mount config directory from step 1
    -v /path/to/config:/opt/tinystash/config \
    # Optional: mount logs directory if you have configured log file(s) in nginx.conf
    -v /var/log/tinystash:/opt/tinystash/logs \
    # host:container port mapping
    -p 80:80 \
    --name tinystash \
    un1def/tinystash
```

3. Set up Telegram bot webhook (Docker container must be started):
```shell
$ docker exec -it tinystash scripts/webhook set
```


### License

Source code is licensed under the [MIT License][license].

Source Sans Pro font is licensed under the [SIL Open Font License, Version 1.1][license-font].



[telegram]: http://telegram.org/
[lua]: https://lua.org/
[openresty]: https://openresty.org/
[openresty_installation]: https://openresty.org/en/installation.html
[tinystash_bot]: https://t.me/tinystash_bot
[license]: https://github.com/un-def/tinystash/blob/master/LICENSE
[license-font]: https://github.com/un-def/tinystash/blob/master/static/OFL.txt
