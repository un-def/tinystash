# ᵗⁱⁿʸ[stash]

[![version](https://img.shields.io/github/tag/un-def/tinystash.svg?maxAge=3600&style=flat-square&label=version)](https://github.com/un-def/tinystash/releases)
[![license](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](https://github.com/un-def/tinystash/blob/master/LICENSE)
[![Docker pulls](https://img.shields.io/docker/pulls/un1def/tinystash.svg?maxAge=3600&style=flat-square)](https://hub.docker.com/r/un1def/tinystash/)

A storage-less database-less file sharing service.

Written in [Lua][lua]. Powered by [LuaJIT][luajit] and [OpenResty][openresty].


## Introduction

**tiny[stash]** is a [website][tinystash-site] and a [Telegram bot][tinystash-bot] for file sharing. A key feature of the service is the fact that it does not actually store anything — all files are stored on Telegram file servers and proxied by the service. You might be familiar with this idea — there is a plenty of file sharing services that work this way. But **tiny[stash]** is going even further. In addition, it does not use any kind of database, all required information is encoded, encrypted and stored directly in a URL.

It is also undemanding in terms of machine resources. If it is possible to run the **nginx** server on some hardware, it'll probably be possible to run **tiny[stash]** too. It also does not require a lot of RAM or disk storage because all data are processed in a streaming fashion.


## Installing

### OpenResty

See [instructions][openresty-installation] on [OpenResty website][openresty].

### Lua packages

```shell
$ while read dep; do opm --cwd get "$dep"; done < requirements.opm
```


## Configuring

```shell
$ cp config.example.lua config.lua
$ vi config.lua
```


## Setting up Telegram bot webhook

```shell
$ ./tinysta.sh webhook set
```


## Running

```shell
$ ./tinysta.sh run
```


## Quick deployment with Docker

1. Prepare `config.lua` as described above.

2. Set up Telegram bot webhook :
```shell
$ docker run --rm -it \
    -v /path/to/config.lua:/opt/tinystash/config.lua \
    un1def/tinystash webhook set
```

3. Run Docker container:
```shell
$ docker run -d \
    --restart unless-stopped \
    -v /path/to/config.lua:/opt/tinystash/config.lua \
    -p 80:80 \
    --name tinystash \
    un1def/tinystash
```


## License

Source code is licensed under the [MIT License][license].

Source Sans Pro font is licensed under the [SIL Open Font License, Version 1.1][license-font-sourcesanspro].

Source Code Pro font is licensed under the [SIL Open Font License, Version 1.1][license-font-sourcecodepro].



[telegram]: http://telegram.org/
[lua]: https://lua.org/
[luajit]: https://luajit.org/
[openresty]: https://openresty.org/
[openresty-installation]: https://openresty.org/en/installation.html
[tinystash-site]: https://tinystash.undef.im/
[tinystash-bot]: https://t.me/tinystash_bot
[license]: https://github.com/un-def/tinystash/blob/master/LICENSE
[license-font-sourcesanspro]: https://github.com/un-def/tinystash/blob/master/static/OFL-SourceSansPro.txt
[license-font-sourcecodepro]: https://github.com/un-def/tinystash/blob/master/static/OFL-SourceCodePro.txt
