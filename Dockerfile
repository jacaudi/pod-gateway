FROM public.ecr.aws/docker/library/alpine:3.21.3

ARG VERSION
ARG REVISION
ARG IMAGE_SOURCE

WORKDIR /

RUN apk add --no-cache \
    coreutils \
    dnsmasq-dnssec \
    iproute2 \
    bind-tools \
    inotify-tools \
    iptables \
    ip6tables \
    curl \
    wget

COPY config /default_config
COPY config /config
COPY bin /bin

LABEL org.opencontainers.image.source="$IMAGE_SOURCE"

CMD [ "/bin/entry.sh" ]
