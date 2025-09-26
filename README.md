# CapwaySync

## Connect to iex on docker
`iex --cookie mycookie --name debug@127.0.0.1 --remsh capway_sync@127.0.0.1`
`{:ok, reason } = Reactor.run(SubscriberSyncWorkflow, %{})`



## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `capway_sync` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:capway_sync, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/capway_sync>.

