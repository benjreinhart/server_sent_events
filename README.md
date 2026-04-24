# ServerSentEvents

[![CI](https://github.com/benjreinhart/server_sent_events/actions/workflows/ci.yml/badge.svg)](https://github.com/benjreinhart/server_sent_events/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/server_sent_events.svg)](https://github.com/benjreinhart/server_sent_events/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/server_sent_events.svg)](https://hexdocs.pm/server_sent_events/readme.html)

Lightweight, fast Server-Sent Events parser for Elixir.

`ServerSentEvents` turns an enumerable of SSE response body chunks into a stream of parsed event maps. The low-level chunk parser is available as `ServerSentEvents.Parser` when you need to manage parser state directly.

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

Parse an enumerable of binary chunks with `ServerSentEvents.parse/1`:

```elixir
events =
  [
    "event: message\n",
    "data: {\"complete\":true}\n\n"
  ]
  |> ServerSentEvents.parse()
  |> Enum.to_list()

IO.inspect(events)
# [%{event: "message", data: "{\"complete\":true}"}]
```

The parser keeps state across arbitrary chunk boundaries:

```elixir
events =
  [
    "event: mes",
    "sage\ndata: {\"complete\":",
    "true}\n\n"
  ]
  |> ServerSentEvents.parse()
  |> Enum.to_list()

IO.inspect(events)
# [%{event: "message", data: "{\"complete\":true}"}]
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

## Req Example

Req can expose the response body as an enumerable with `into: :self`. That body can be passed through `ServerSentEvents.parse/1`:

```elixir
%Req.Response{status: 200, body: response_body} =
  Req.post!("https://api.anthropic.com/v1/messages",
    json: request,
    into: :self,
    headers: %{
      "x-api-key" => api_key(),
      "anthropic-version" => "2023-06-01"
    }
  )

response_body
|> ServerSentEvents.parse()
|> Enum.each(fn event ->
  # Do something with event
end)
```

Callers typically filter event types and JSON-decode the `data` field after parsing.

## Benchmarking

Run the local benchmark with:

```sh
mix bench
```

The benchmark exercises both large complete payloads and large payloads that end with an incomplete trailing event, and reports execution time and memory usage.
