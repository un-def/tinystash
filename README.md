# ᵗⁱⁿʸ[stash]

------------------------------------------------------------------------------

A storage-less, database-less, \_\_\_\_\_\_\_\_-less filesharing. Send anything to [@tinystash_bot][tinystash_bot] [Telegram][telegram] bot. Get an opaque http link. Share it.

Written in [Lua][lua]. Powered by [OpenResty][openresty].

**The tinystash project is under (not so) heavy development and not ready for daily use.**

------------------------------------------------------------------------------


### Installing

#### Lua packages

```shell
$ while read PNAME; do opm --cwd get $PNAME; done < requirements.opm
```


### Configuring

Copy app and nginx configs from examples and edit them:

```shell
$ cp config.example.lua config.lua
$ cp conf/nginx.example.conf conf/nginx.conf
```


### Running

```shell
$ /path/to/openresty/nginx/sbin/nginx -c conf/nginx.conf -p .
```


[telegram]: http://telegram.org/
[lua]: https://lua.org/
[openresty]: https://openresty.org/
[tinystash_bot]: https://t.me/tinystash_bot
