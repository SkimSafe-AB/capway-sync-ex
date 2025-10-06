FROM elixir:1.18 AS build
RUN apt-get update && apt-get upgrade -y

ENV MIX_ENV=prod

RUN mkdir /app
WORKDIR /app
RUN mkdir keys
RUN mkdir elixir_cache
COPY mix.exs mix.lock ./

RUN mix local.hex --force \
  && mix local.rebar --force

COPY config config

RUN MIX_ENV=prod mix deps.compile
RUN MIX_ENV=test mix deps.compile
RUN mv /app/deps /app/elixir_cache/deps_cache

FROM scratch AS export-stage
COPY --from=build /app/elixir_cache .
