FROM openresty/openresty:alpine AS builder
WORKDIR /opt/tinystash/
RUN apk add --no-cache curl perl
COPY requirements.opm /tmp/requirements.opm
RUN while read dep; do opm --cwd get "$dep"; done < /tmp/requirements.opm
COPY app/ app/
COPY scripts/ scripts/
COPY static/ static/
COPY templates/ templates/
COPY tinysta.sh tinysta.sh

FROM openresty/openresty:alpine
WORKDIR /opt/tinystash/
RUN apk add --no-cache ca-certificates
COPY --from=builder /opt/tinystash/ ./

EXPOSE 80

ENTRYPOINT ["./tinysta.sh"]
CMD ["run"]

LABEL maintainer="un.def <me@undef.im>"
LABEL version="2.0.0"
