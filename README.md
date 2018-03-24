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


### Running

```shell
$ cd /path/to/tinystash
$ /path/to/openresty/nginx/sbin/nginx -c config/nginx.conf -p .
```


### License

[MIT License][license]



[telegram]: http://telegram.org/
[lua]: https://lua.org/
[openresty]: https://openresty.org/
[openresty_installation]: https://openresty.org/en/installation.html
[tinystash_bot]: https://t.me/tinystash_bot
[license]: https://github.com/un-def/tinystash/blob/master/LICENSE
