FROM elixir:1.18 AS build

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y inotify-tools locales

# Generate locale for UTF-8
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
  locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8 \
  LANGUAGE=en_US:en \
  LC_ALL=en_US.UTF-8 \
  MIX_ENV=prod

RUN mkdir /app
WORKDIR /app
RUN mkdir keys \
  && mkdir deps \
  && mkdir _build

COPY mix.exs mix.lock ./
COPY elixir_cache/deps_cache /app/deps
COPY elixir_cache/_build /app/_build

RUN mix local.hex --force \
  && mix local.rebar --force

COPY config config
COPY lib lib
COPY rel rel

WORKDIR /app

RUN mix release

FROM bitnami/minideb:latest
RUN apt-get update && apt-get upgrade -y && apt-get install openssl ca-certificates locales -y

# Generate locale for UTF-8
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
  locale-gen en_US.UTF-8

# Set environment variables to use UTF-8
ENV LANG=en_US.UTF-8 \
  LANGUAGE=en_US:en \
  LC_ALL=en_US.UTF-8 \
  MIX_ENV=prod

EXPOSE 4000

RUN mkdir /app
WORKDIR /app

COPY --from=build /app/_build/prod/rel/capway_sync .
ENV HOME=/app
CMD ["/bin/bash", "-c", "/app/bin/capway_sync start"]
