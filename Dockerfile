FROM public.ecr.aws/docker/library/alpine:3.21.3@sha256:a8560b36e8b8210634f77d9f7f9efd7ffa463e380b75e2e74aff4511df3ef88c

ARG VERSION
ARG REVISION
ARG IMAGE_SOURCE

WORKDIR /

# iproute2 -> bridge
# bind-tools -> dig, bind
# dhclient -> get dynamic IP
# dnsmasq-dnssec -> DNS & DHCP server with DNSSEC support
# coreutils -> need REAL chown and chmod for dhclient (it uses reference option not supported in busybox)
# bash -> for scripting logic
# inotify-tools -> inotifyd for dnsmask resolv.conf reload circumvention

RUN apk add --no-cache coreutils dnsmasq-dnssec \
    iproute2 bind-tools bash inotify-tools ip6tables

COPY config /default_config
COPY config /config
COPY bin /bin

LABEL org.opencontainers.image.source $IMAGE_SOURCE

CMD [ "/bin/entry.sh" ]
