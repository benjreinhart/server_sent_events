defmodule ServerSentEvents do
  @moduledoc """
  This module exposes a streaming parser for Server Sent Events. See the [official
  specification](https://html.spec.whatwg.org/multipage/server-sent-events.html) for
  details on parsing and interpreting the event stream.

  This library is focused on parsing the event stream itself, and does not provide
  behavior regarding the management of the underlying HTTP connection or EventSource
  state outside a single event. It parses `id` fields as binaries, ignoring any `id`
  field that contains a NULL byte. It parses `retry` fields as non-negative integers,
  ignoring invalid values. It emits only events that contain a `data` field. Callers
  are still responsible for behavior such as tracking, resetting, and applying the
  last event ID, applying retry delays, reconnecting, interpreting response headers,
  and deciding how to consume event data.
  """

  alias ServerSentEvents.Parser

  @type event :: %{
          required(:data) => binary(),
          optional(:event) => binary(),
          optional(:id) => binary(),
          optional(:retry) => non_neg_integer()
        }

  @doc """
  Lazily parses an enumerable of binary chunks into an event stream.

  Each emitted item is one parsed event map. Parser state is retained between
  chunks, so callers can pass arbitrary response body chunks directly.

  ## Examples

      iex> events =
      ...>   [
      ...>     "id: 1\\n",
      ...>     "event: message\\n",
      ...>     "retry: 5000\\n",
      ...>     "data: hello\\n\\n"
      ...>   ]
      ...>   |> ServerSentEvents.parse()
      ...>   |> Enum.to_list()
      iex> events == [%{id: "1", event: "message", retry: 5000, data: "hello"}]
      true
  """
  @spec parse(Enumerable.t()) :: Enumerable.t(event())
  def parse(stream) do
    Stream.transform(stream, %Parser{phase: :start}, fn chunk, state ->
      Parser.parse(state, chunk)
    end)
  end
end
