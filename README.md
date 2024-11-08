# ServerSentEvents

This module implements a performant [Server Sent Event](https://en.wikipedia.org/wiki/Server-sent_events) parser. It supports parsing a chunk of data containing a single event, a chunk of data containing multiple events, a chunk of data containing an incomplete event, and a mix thereof.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `server_sent_events` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:server_sent_events, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
ServerSentEvents.parse("event: event\\ndata: {\\"complete\\":true}\\n\\n")
# {[%{"event" => "event", "data" => "{\\"complete\\":true}\\n"}], ""}
```
