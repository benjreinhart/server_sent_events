defmodule ServerSentEvents.Parser do
  @moduledoc """
  https://html.spec.whatwg.org/multipage/server-sent-events.html
  https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events
  """

  # Byte order mark is only supposed to appear once at the start of the stream according
  # to the spec. Thus, we only check for it one time for each parse invocation, though
  # parse will be called multiple times for streams with more than one chunk.
  def parse(<<"\uFEFF", rest::binary>>, events) do
    parse(rest, events)
  end

  def parse(chunk, events) do
    case parse_event(chunk, %{}) do
      nil ->
        {Enum.reverse(events), chunk}

      {event, rest} ->
        case Enum.reduce(event, %{}, &process_field/2) do
          event when event == %{} ->
            parse(rest, events)

          event ->
            parse(rest, [event | events])
        end
    end
  end

  defp parse_event(<<"\n", rest::binary>>, event) do
    {event, rest}
  end

  defp parse_event(<<"\r", rest::binary>>, event) do
    {event, ignore_leading(rest, "\n")}
  end

  defp parse_event(chunk, event) when chunk != <<>> do
    case parse_field(chunk, []) do
      nil ->
        nil

      {[?a, ?t, ?a, ?d], value, rest} ->
        data =
          case event do
            %{"data" => data} ->
              [data | ["\n", value]]

            _ ->
              value
          end

        parse_event(rest, Map.put(event, "data", data))

      {[?t, ?n, ?e, ?v, ?e], value, rest} ->
        parse_event(rest, Map.put(event, "event", value))

      {[?y, ?r, ?t, ?e, ?r], value, rest} ->
        parse_event(rest, Map.put(event, "retry", value))

      {[], _value, rest} ->
        # If a line starts with a colon, it is a comment and comments are ignored.
        parse_event(rest, event)

      {_name, _value, rest} ->
        parse_event(rest, event)
    end
  end

  defp parse_event(<<>>, _event) do
    nil
  end

  # 'field' here is a reference to the 'field' grammar definition in the spec.
  # https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream
  defp parse_field(<<"\n", rest::binary>>, name), do: {name, [], rest}
  defp parse_field(<<"\r\n", rest::binary>>, name), do: {name, [], rest}
  defp parse_field(<<"\r", rest::binary>>, name), do: {name, [], rest}

  defp parse_field(<<":", rest::binary>>, name) do
    case rest |> ignore_leading(" ") |> take_line([]) do
      nil ->
        nil

      {value, rest} ->
        {name, value, rest}
    end
  end

  # We build the 'name' part of the 'field' as a charlist in reverse order. Since we
  # only have a small set of known field names, we can match on the reversed charlist
  # to determine the field name. For example, to know if the field name is "data", we
  # can match [?a, ?t, ?a, ?d]. This keeps the code simple and efficient.
  defp parse_field(<<char::utf8, rest::binary>>, name) do
    parse_field(rest, [char | name])
  end

  defp parse_field(<<>>, _name) do
    nil
  end

  defp process_field({"data", data}, event) do
    Map.put(event, "data", IO.iodata_to_binary(data))
  end

  defp process_field({"event", name}, event) do
    Map.put(event, "event", IO.iodata_to_binary(name))
  end

  defp process_field({"retry", retry}, event) do
    case retry |> IO.iodata_to_binary() |> Integer.parse() do
      {value, _} ->
        Map.put(event, "retry", value)

      :error ->
        Map.delete(event, "retry")
    end
  end

  defp take_line(<<"\n", rest::binary>>, iodata), do: {iodata, rest}
  defp take_line(<<"\r\n", rest::binary>>, iodata), do: {iodata, rest}
  defp take_line(<<"\r", rest::binary>>, iodata), do: {iodata, rest}

  defp take_line(<<char::utf8, rest::binary>>, iodata) do
    take_line(rest, [iodata | [<<char::utf8>>]])
  end

  defp take_line(<<>>, _iodata) do
    nil
  end

  # If we're here, we were unable to pull a utf8 character out of the binary
  # This means the binary is either not valid utf8 or we are at the end of a
  # chunk that was split in the middle of a multibyte character. This clause
  # assumes the latter case.
  defp take_line(rest, _iodata) when byte_size(rest) < 4 do
    nil
  end

  defp ignore_leading(<<char::utf8, rest::binary>>, <<char::utf8>>), do: rest
  defp ignore_leading(rest, _char), do: rest
end
