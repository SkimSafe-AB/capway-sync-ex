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
COPY bundle_portal.key /app/keys/

RUN mix archive.install github hexpm/hex branch latest --force

RUN mix hex.repo add bundle_portal https://hex-repo.s3.eu-central-1.amazonaws.com/public --public-key=/app/keys/bundle_portal.key \
  && mix deps.get

RUN MIX_ENV=prod mix deps.compile
RUN MIX_ENV=test mix deps.compile
RUN mv /app/_build /app/elixir_cache/_build
RUN mv /app/deps /app/elixir_cache/deps_cache

FROM scratch AS export-stage
COPY --from=build /app/elixir_cache .
