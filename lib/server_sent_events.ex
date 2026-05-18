defmodule ServerSentEvents do
  @moduledoc """
  This module exposes a streaming decoder for Server Sent Events. See the [official
  specification](https://html.spec.whatwg.org/multipage/server-sent-events.html) for
  details on parsing and interpreting the event stream.

  This library is focused on decoding the event stream itself, and does not provide
  behavior regarding the management of the underlying HTTP connection or EventSource
  state outside a single event. It decodes `id` fields as binaries, ignoring any `id`
  field that contains a NULL byte. It decodes `retry` fields as non-negative integers,
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

  @opaque state :: Parser.state()

  @doc """
  Creates new parser state that can be then passed to `parse/2`
  """
  @spec new() :: state()
  defdelegate new(), to: Parser

  @doc """
  Lazily decodes an enumerable of binary chunks into an event stream.

  Each emitted item is one decoded event map. Decoder state is retained between
  chunks, so callers can pass arbitrary response body chunks directly.

  ## Examples

      iex> events =
      ...>   [
      ...>     "id: 1\\n",
      ...>     "event: message\\n",
      ...>     "retry: 5000\\n",
      ...>     "data: hello\\n\\n"
      ...>   ]
      ...>   |> ServerSentEvents.decode_stream()
      ...>   |> Enum.to_list()
      iex> events == [%{id: "1", event: "message", retry: 5000, data: "hello"}]
      true
  """
  @spec decode_stream(Enumerable.t()) :: Enumerable.t(event())
  def decode_stream(stream) do
    Stream.transform(stream, new(), fn chunk, state ->
      Parser.parse(state, chunk)
    end)
  end

  @doc """
  Parses binary chunk and returns complete events and an active state

  ## Examples

      iex> ServerSentEvents.parse("id: 1\\nevent: message\\nretry: 5000\\ndata: hello\\n\\n")
      {[%{data: "hello", id: "1", retry: 5000, event: "message"}],
      %ServerSentEvents.Parser{phase: :field, key: nil, value: nil, event: nil}}
  """
  @spec parse(input :: binary()) :: {[event()], state()}
  defdelegate parse(input), to: Parser

  @doc """
  Parses binary chunk using existing parser state and returns complete events
  and an updated state

  ## Examples

      iex> state = ServerSentEvents.new()
      %ServerSentEvents.Parser{phase: :start, key: nil, value: nil, event: nil}
      iex> {_, state} = ServerSentEvents.Parser.parse(state, "id: 1\\nevent: message\\n")
      {[],
      %ServerSentEvents.Parser{
        phase: :field,
        key: nil,
        value: nil,
        event: %{id: "1", event: "message"}
      }}
      iex> {_, state} = ServerSentEvents.parse(state, "retry: 5000\\ndata: hello\\n\\n")
      {[%{data: "hello", id: "1", retry: 5000, event: "message"}],
      %ServerSentEvents.Parser{phase: :field, key: nil, value: nil, event: nil}}
  """
  @spec parse(state(), input :: binary()) :: {[event()], state()}
  defdelegate parse(state, input), to: Parser
end
