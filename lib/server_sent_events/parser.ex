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
    case rest do
      <<"\n", rest::binary>> -> {event, rest}
      _ -> {event, rest}
    end
  end

  defp parse_event(<<"data:", rest::binary>>, event) do
    case rest |> ignore_single_leading_space() |> take_line([]) do
      nil ->
        nil

      {line, rest} ->
        event =
          event
          |> build_event_when_nil()
          |> Map.update!("data", &[&1 | [line, "\n"]])

        parse_event(rest, event)
    end
  end

  defp parse_event(<<"event:", rest::binary>>, event) do
    case rest |> ignore_single_leading_space() |> take_line([]) do
      nil ->
        nil

      {line, rest} ->
        event =
          event
          |> build_event_when_nil()
          |> Map.put("event", line)

        parse_event(rest, event)
    end
  end

  defp parse_event("", _event) do
    nil
  end

  defp parse_event(<<":", rest::binary>>, event) do
    case take_line(rest, []) do
      nil ->
        nil

      {_line, rest} ->
        parse_event(rest, event)
    end
  end

  defp parse_event(<<"\uFEFF", rest::binary>>, event) do
    {event, rest}
  end

  defp process_event(%{"event" => event, "data" => data}) do
    %{"event" => IO.iodata_to_binary(event), "data" => IO.iodata_to_binary(data)}
  end

  defp build_event_when_nil(nil), do: %{"event" => "", "data" => ""}
  defp build_event_when_nil(e), do: e

  defp take_line(<<>>, _iodata), do: nil
  defp take_line(<<"\n", rest::binary>>, iodata), do: {iodata, rest}
  defp take_line(<<"\r\n", rest::binary>>, iodata), do: {iodata, rest}
  defp take_line(<<"\r", rest::binary>>, iodata), do: {iodata, rest}

  defp take_line(<<char::utf8, rest::binary>>, iodata) do
    take_line(rest, [iodata | [<<char::utf8>>]])
  end

  defp ignore_single_leading_space(<<" ", rest::binary>>), do: rest
  defp ignore_single_leading_space(rest), do: rest
end
