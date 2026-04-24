defmodule ServerSentEvents do
  @moduledoc """
  This module exposes a streaming parser for Server Sent Events. See the [official
  specification](https://html.spec.whatwg.org/multipage/server-sent-events.html) for
  details on parsing and interpreting the event stream.

  Note this library is focused on parsing the event stream itself, and does not provide
  behavior regarding the interpretation of the event data or the management of the underlying
  HTTP connection. For example, the `retry` field is parsed and included in the emitted event
  maps, but it is up to the caller to decide how to interpret it (e.g. as an integer) and what
  to do with it. The same goes for the `id` field and the `Last-Event-ID` behavior.
  """

  alias ServerSentEvents.Parser

  @type event :: %{
          optional(:data) => binary(),
          optional(:event) => binary(),
          optional(:id) => binary(),
          optional(:retry) => binary()
        }

  @doc """
  Lazily parses an enumerable of binary chunks into an event stream.

  Each emitted item is one parsed event map. Parser state is retained between
  chunks, so callers can pass arbitrary response body chunks directly.
  """
  @spec parse(Enumerable.t()) :: Enumerable.t(event())
  def parse(stream) do
    Stream.transform(stream, %Parser{phase: :start}, fn chunk, state ->
      {state, events} = Parser.parse(state, chunk)
      {events, state}
    end)
  end
end
