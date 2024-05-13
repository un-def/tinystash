FROM openresty/openresty:alpine AS builder
WORKDIR /opt/tinystash/
RUN apk add --no-cache curl perl
COPY requirements.opm /tmp/requirements.opm
RUN while read dep; do opm --cwd get "$dep"; done < /tmp/requirements.opm
COPY app/ app/
COPY static/ static/
COPY templates/ templates/
COPY commands/ commands/
COPY tinysta.sh tinysta.sh
COPY nginx.conf.tpl nginx.conf.tpl

FROM openresty/openresty:alpine-apk
WORKDIR /opt/tinystash/
RUN apk add --no-cache ca-certificates
COPY --from=builder /opt/tinystash/ ./

EXPOSE 80

ENTRYPOINT ["./tinysta.sh"]
CMD ["run"]

LABEL maintainer="Dmitry Meyer <me@undef.im>"
LABEL version="2.3.0"
