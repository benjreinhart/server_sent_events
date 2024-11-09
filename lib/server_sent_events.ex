defmodule ServerSentEvents do
  @moduledoc """
  This module implements a performant [Server Sent Event](https://en.wikipedia.org/wiki/Server-sent_events).
  It supports parsing a chunk of data containing a single event, a chunk of data containing multiple events,
  a chunk of data containing an incomplete event, and a mix thereof.

  The parser is conformant to the [official Server-Sent Events spec](https://html.spec.whatwg.org/multipage/server-sent-events.html).
  """

  @doc ~s"""
  Parses a chunk of data into a list of SSE messages.

  Returns a tuple containing the list of parsed events and the remaining data
  from the chunk if it contained an incomplete event.

  ## Examples

      iex> ServerSentEvents.parse("event: event\\ndata: {\\"complete\\":")
      {[], "event: event\\ndata: {\\"complete\\":"}

      iex> ServerSentEvents.parse("event: event\\ndata: {\\"complete\\":true}\\n\\n")
      {[%{"event" => "event", "data" => "{\\"complete\\":true}"}], ""}

  """
  def parse(chunk) when is_binary(chunk) do
    ServerSentEvents.Parser.parse(chunk, [])
  end
end
