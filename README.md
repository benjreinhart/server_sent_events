# ServerSentEvents

This module implements a performant [Server Sent Event](https://en.wikipedia.org/wiki/Server-sent_events) parser.

## Usage

```elixir
{events, rest} = ServerSentEvents.parse("event: event\ndata: {\"complete\":true}\n\n")
IO.inspect(events)   # [%{"event" => "event", "data" => "{\"complete\":true}\n"}]
IO.inspect(rest)     # ""
```

Parsing a chunk containing zero or more events followed by an incomplete event returns the incomplete data.

```elixir
{events, buffer} = ServerSentEvents.parse("event: event\ndata: {\"complete\":")
IO.inspect(events)   # []
IO.inspect(buffer)   # "event: event\ndata: {\"complete\":"

{events, buffer} = ServerSentEvents.parse(buffer <> "true}\n\nevent: event\ndata: {")
IO.inspect(events)   # [%{"event" => "event", "data" => "{\"complete\":true}\n"}]
IO.inspect(buffer)   # "event: event\ndata: {"

{events, rest} = ServerSentEvents.parse(buffer <> "\"key\":\"value\"}\n\n")
IO.inspect(events)   # [%{"event" => "event", "data" => "{\"key\":\"value\"}\n"}]
IO.inspect(rest)     # ""
```

This can be useful for environments where events may not reliably arrive in one piece.

## Installation

The package can be installed by adding `server_sent_events` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:server_sent_events, "~> 0.1.0"}
  ]
end
```
