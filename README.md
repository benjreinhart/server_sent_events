# ServerSentEvents

[![CI](https://github.com/benjreinhart/server_sent_events/actions/workflows/ci.yml/badge.svg)](https://github.com/benjreinhart/server_sent_events/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/server_sent_events.svg)](https://github.com/benjreinhart/server_sent_events/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/server_sent_events.svg)](https://hexdocs.pm/server_sent_events/readme.html)

Lightweight, fast Server-Sent Events parser for Elixir.

`ServerSentEvents` is a low-level parser for the SSE event stream format. It turns stream bytes into parsed event maps and keeps enough parser state to resume across arbitrary chunk boundaries.

## Installation

The package can be installed by adding `server_sent_events` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:server_sent_events, "~> 1.0.0"}
  ]
end
```

## Usage

Parse a complete event stream chunk with `parse/1`:

```elixir
{state, events} =
  ServerSentEvents.parse("event: message\ndata: {\"complete\":true}\n\n")

IO.inspect(events)
# [%{event: "message", data: "{\"complete\":true}"}]
```

The returned `state` should be passed to `parse/2` with the next chunk from the same stream:

```elixir
{state, []} =
  ServerSentEvents.parse("event: message\ndata: {\"complete\":")

{state, events} =
  ServerSentEvents.parse(state, "true}\n\n")

IO.inspect(events)
# [%{event: "message", data: "{\"complete\":true}"}]
```

A chunk may contain zero events, one event, many events, or the beginning of an event that completes in a later chunk.

```elixir
{state, events} =
  ServerSentEvents.parse("""
  event: first
  data: one

  event: second
  data: two

  """)

IO.inspect(events)
# [%{event: "first", data: "one"}]

{_state, events} = ServerSentEvents.parse(state, "\n")

IO.inspect(events)
# [%{event: "second", data: "two"}]
```

Events are maps with one or more of the following keys: `:id`, `:event`, `:data`, or `:retry`.

## Parser Boundary

This library parses the event stream syntax. It intentionally leaves EventSource semantics to the caller, including:

- Tracking or applying `lastEventId`.
- Validating, converting, or applying `retry`.
- Suppressing events that do not contain a `data` field.
- Supplying a default event type such as `"message"`.
- Opening HTTP connections, reconnecting, or interpreting response headers.

This parser also assumes the input stream is UTF-8. It does not validate UTF-8, reject malformed input, or perform replacement-character decoding.

## Real-World Example

AI providers such as Anthropic and OpenAI stream generated messages using Server-Sent Events. The parser can be used inside a streaming HTTP response handler by storing the parser state between chunks:

```elixir
Req.post("https://api.anthropic.com/v1/messages",
  json: request,
  into: fn {:data, data}, {req, res} ->
    {state, events} =
      case Request.get_private(req, :sse_state) do
        nil -> ServerSentEvents.parse(data)
        state -> ServerSentEvents.parse(state, data)
      end

    req = Request.put_private(req, :sse_state, state)

    if events != [] do
      send(pid, {:events, events})
    end

    {:cont, {req, res}}
  end,
  headers: %{
    "x-api-key" => api_key(),
    "anthropic-version" => "2023-06-01"
  }
)
```

Parsed events are returned as maps:

```elixir
{_state, events} =
  ServerSentEvents.parse("""
  event: content_block_delta
  data: {"type":"content_block_delta","index":0}

  event: ping
  data: {"type":"ping"}

  """)

IO.inspect(events)
# [
#   %{event: "content_block_delta", data: "{\"type\":\"content_block_delta\",\"index\":0}"},
#   %{event: "ping", data: "{\"type\":\"ping\"}"}
# ]
```

Callers typically filter event types and JSON-decode the `data` field after parsing.

## Benchmarking

Run the local benchmark with:

```sh
mix bench
```

The benchmark exercises both large complete payloads and large payloads that end with an incomplete trailing event, and reports execution time and memory usage.
