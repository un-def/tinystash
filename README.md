# ᵗⁱⁿʸ[stash]


A storage-less, database-less, \_\_\_\_\_\_\_\_-less filesharing. Send anything to [@tinystash_bot][tinystash_bot] [Telegram][telegram] bot. Get an opaque http link. Share it.

Written in [Lua][lua]. Powered by [OpenResty][openresty].


### Installing

#### OpenResty

See [instructions][openresty_installation] on [OpenResty website][openresty].

#### Lua packages

```shell
$ while read PNAME; do opm --cwd get $PNAME; done < requirements.opm
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

[MIT License][license]



[telegram]: http://telegram.org/
[lua]: https://lua.org/
[openresty]: https://openresty.org/
[openresty_installation]: https://openresty.org/en/installation.html
[tinystash_bot]: https://t.me/tinystash_bot
[license]: https://github.com/un-def/tinystash/blob/master/LICENSE
