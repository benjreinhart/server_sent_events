defmodule ServerSentEvents.Parser do
  @moduledoc """
  https://html.spec.whatwg.org/multipage/server-sent-events.html
  https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events
  """

  def parse(chunk, events) do
    case parse_event(chunk, nil) do
      nil ->
        {Enum.reverse(events), chunk}

      {nil, rest} ->
        parse(rest, events)

      {event, rest} ->
        parse(rest, [process_event(event) | events])
    end
  end

  defp parse_event(<<"\n", rest::binary>>, event) do
    {event, rest}
  end

  defp parse_event(<<"\r", rest::binary>>, event) do
    {event, ignore_leading(rest, "\n")}
  end

  defp parse_event(<<"data", rest::binary>>, event) do
    case rest do
      <<":", rest::binary>> ->
        case rest |> ignore_leading(" ") |> take_line([]) do
          nil ->
            nil

          {line, rest} ->
            parse_event_with_data(rest, event, [line], ["\n", line])
        end

      <<"\n", rest::binary>> ->
        parse_event_with_data(rest, event, [""], ["\n"])

      <<"\r\n", rest::binary>> ->
        parse_event_with_data(rest, event, [""], ["\n"])

      <<"\r", rest::binary>> ->
        parse_event_with_data(rest, event, [""], ["\n"])

      rest ->
        case ignore_line(rest) do
          nil ->
            nil

          rest ->
            parse_event(rest, event)
        end
    end
  end

  defp parse_event(<<"event", rest::binary>>, event) do
    case rest do
      <<":", rest::binary>> ->
        case rest |> ignore_leading(" ") |> take_line([]) do
          nil ->
            nil

          {line, rest} ->
            parse_event(rest, update_event(event, "event", fn _ -> line end))
        end

      <<"\n", rest::binary>> ->
        parse_event(rest, update_event(event, "event", fn _ -> "" end))

      <<"\r\n", rest::binary>> ->
        parse_event(rest, update_event(event, "event", fn _ -> "" end))

      <<"\r", rest::binary>> ->
        parse_event(rest, update_event(event, "event", fn _ -> "" end))

      rest ->
        case ignore_line(rest) do
          nil ->
            nil

          rest ->
            parse_event(rest, event)
        end
    end
  end

  defp parse_event(<<>>, _event) do
    nil
  end

  # Comments are ignored
  defp parse_event(<<":", rest::binary>>, event) do
    case ignore_line(rest) do
      nil ->
        nil

      rest ->
        parse_event(rest, event)
    end
  end

  # Byte-order mark (BOM) is ignored
  defp parse_event(<<"\uFEFF", rest::binary>>, event) do
    {event, rest}
  end

  defp parse_event_with_data(rest, event, initial_data, additional_data) do
    parse_event(
      rest,
      update_event(event, "data", fn
        nil -> initial_data
        data -> [data | additional_data]
      end)
    )
  end

  defp process_event(event) when not is_nil(event) do
    event
    |> Enum.map(fn {k, v} -> {k, IO.iodata_to_binary(v)} end)
    |> Map.new()
  end

  defp update_event(event, key, updater_fun) do
    (event || %{})
    |> Map.put_new(key, nil)
    |> Map.update!(key, updater_fun)
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

  defp ignore_line(<<"\n", rest::binary>>), do: rest
  defp ignore_line(<<"\r\n", rest::binary>>), do: rest
  defp ignore_line(<<"\r", rest::binary>>), do: rest
  defp ignore_line(<<_char::utf8, rest::binary>>), do: ignore_line(rest)
  defp ignore_line(<<>>), do: nil
end
