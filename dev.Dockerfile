FROM elixir:1.18

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y inotify-tools fswatch

COPY . /app

WORKDIR /app
RUN mix local.hex --force
RUN mix local.rebar --force

RUN mix archive.install hex phx
# Add our private repo
# COPY certs/bundle_portal.key /app/certs/
# RUN mix hex.repo add bundle_portal https://hex-repo.s3.eu-central-1.amazonaws.com/public --public-key=/app/certs/bundle_portal.key

RUN mix deps.clean --all
RUN mix deps.get
RUN mix compile

CMD ["iex", "--sname", "capway_sync_node", "-S", "mix"]
