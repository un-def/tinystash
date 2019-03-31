FROM openresty/openresty:alpine AS build
WORKDIR /opt/tinystash/
RUN apk add --no-cache curl perl
COPY requirements.opm /tmp/requirements.opm
RUN while read PNAME; do opm --cwd get $PNAME; done < /tmp/requirements.opm
COPY app/ app/
COPY scripts/ scripts/
COPY static/ static/
COPY templates/ templates/

FROM openresty/openresty:alpine
WORKDIR /opt/tinystash/
RUN apk add --no-cache ca-certificates
COPY --from=build /opt/tinystash/ ./

EXPOSE 80

ENTRYPOINT ["/usr/local/openresty/bin/openresty"]
CMD ["-c", "config/nginx.conf", "-p", "."]

LABEL maintainer="un.def <me@undef.im>"
LABEL version="1.0.0"
