defmodule ServerSentEvents.Parser do
  @moduledoc """
  https://html.spec.whatwg.org/multipage/server-sent-events.html
  https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events
  """
  def parse(chunk, events) do
    case parse_event(chunk, %{"event" => [], "data" => []}) do
      nil ->
        {Enum.reverse(events), chunk}

      {event, ""} ->
        {Enum.reverse([process_event(event) | events]), ""}

      {event, rest} ->
        parse(rest, [process_event(event) | events])
    end
  end

  defp parse_event(<<"data:", rest::binary>>, event) do
    case rest |> ignore_single_leading_space() |> take_line([]) do
      nil ->
        nil

      {line, rest} ->
        parse_event(rest, Map.update!(event, "data", &[&1, line | ["\n"]]))
    end
  end

  defp parse_event(<<"event:", rest::binary>>, event) do
    case rest |> ignore_single_leading_space() |> take_line([]) do
      nil ->
        nil

      {line, rest} ->
        parse_event(rest, Map.put(event, "event", line))
    end
  end

  defp parse_event(<<"\n", rest::binary>>, event) do
    {event, rest}
  end

  defp parse_event(<<"\r\n", rest::binary>>, event) do
    {event, rest}
  end

  defp parse_event(<<"\r", rest::binary>>, event) do
    {event, rest}
  end

  defp parse_event(<<>>, _event) do
    nil
  end

  defp process_event(%{"event" => event, "data" => data}) do
    %{"event" => IO.iodata_to_binary(event), "data" => IO.iodata_to_binary(data)}
  end

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
