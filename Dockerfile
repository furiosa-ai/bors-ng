ARG ELIXIR_VERSION=1.14.5
ARG SOURCE_COMMIT

# Alpine-based builder: musl libc avoids QEMU x86_64 emulation instability
# that crashes the Erlang VM on arm64 hosts building amd64 images
FROM elixir:${ELIXIR_VERSION}-alpine AS builder

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apk add --no-cache \
    build-base libtool autoconf automake curl git nodejs npm

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix hex.info

WORKDIR /src
ADD ./ /src/

ENV ALLOW_PRIVATE_REPOS=true
ENV MIX_ENV=prod

RUN mix deps.get
RUN cd /src/assets && npm install && npm run deploy
RUN mix phx.digest
RUN mix distillery.release --env=$MIX_ENV

# Make the git HEAD available to the released app
RUN if [ -d .git ]; then \
        mkdir /src/_build/prod/rel/bors/.git && \
        git rev-parse --short HEAD > /src/_build/prod/rel/bors/.git/HEAD; \
    elif [ -n ${SOURCE_COMMIT} ]; then \
        mkdir /src/_build/prod/rel/bors/.git && \
        echo ${SOURCE_COMMIT} > /src/_build/prod/rel/bors/.git/HEAD; \
    fi

####

FROM alpine:3.19
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=C.UTF-8

# openssl: SSL/TLS, ncurses-libs: Erlang terminal, libgcc/libstdc++: ERTS runtime deps
RUN apk add --no-cache \
    bash git openssl ncurses-libs libgcc libstdc++ curl

ADD ./script/docker-entrypoint /usr/local/bin/bors-ng-entrypoint
COPY --from=builder /src/_build/prod/rel/ /app/

RUN curl -Ls https://github.com/bors-ng/dockerize/releases/download/v0.7.12/dockerize-linux-amd64-v0.7.12.tar.gz | \
    tar xzv -C /usr/local/bin && \
    /app/bors/bin/bors describe

ENV PORT=4000
ENV DATABASE_AUTO_MIGRATE=true
ENV ALLOW_PRIVATE_REPOS=true

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/bors-ng-entrypoint"]
CMD ["./bors/bin/bors", "foreground"]

EXPOSE 4000
