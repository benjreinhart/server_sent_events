defmodule ServerSentEvents.Bench do
  alias ServerSentEvents.Parser

  @target_sizes [
    {"1 MB", 1_048_576},
    {"4 MB", 4_194_304}
  ]

  @data_lines_per_event 8
  @data_chunk String.duplicate("abcdefghijklmnopqrstuvwxyz0123456789", 16)
  @incomplete_trim_bytes 97

  def run do
    inputs = inputs()

    print_inputs(inputs)

    Benchee.run(
      %{
        "complete large payload" => &parse_complete!/1,
        "incomplete large payload" => &parse_incomplete!/1
      },
      inputs: inputs,
      memory_time: 2,
      reduction_time: 0,
      time: 5,
      warmup: 2
    )
  end

  defp inputs do
    Map.new(@target_sizes, fn {label, target_bytes} ->
      {label, build_input(target_bytes)}
    end)
  end

  defp build_input(target_bytes) do
    events = build_events(target_bytes)
    complete_payload = IO.iodata_to_binary(events)
    complete_event_count = length(events)

    if complete_event_count < 2 do
      raise "expected at least two events for benchmark input generation"
    end

    last_event = List.last(events)
    incomplete_last_event_size = byte_size(last_event) - @incomplete_trim_bytes

    if incomplete_last_event_size <= 0 do
      raise "trailing event trim removed the entire event"
    end

    prefix_size = byte_size(complete_payload) - byte_size(last_event)

    incomplete_payload =
      binary_part(complete_payload, 0, prefix_size) <>
        binary_part(last_event, 0, incomplete_last_event_size)

    %{
      complete_event_count: complete_event_count,
      complete_payload: complete_payload,
      incomplete_complete_event_count: complete_event_count - 1,
      incomplete_payload: incomplete_payload,
      incomplete_rest_bytes: incomplete_last_event_size
    }
  end

  defp build_events(target_bytes) do
    1
    |> Stream.iterate(&(&1 + 1))
    |> Enum.reduce_while({[], 0}, fn id, {events, total_bytes} ->
      event = build_event(id)
      next_total_bytes = total_bytes + byte_size(event)

      cond do
        next_total_bytes < target_bytes ->
          {:cont, {[event | events], next_total_bytes}}

        events == [] ->
          {:cont, {[event | events], next_total_bytes}}

        true ->
          {:halt, Enum.reverse([event | events])}
      end
    end)
  end

  defp build_event(id) do
    [
      "id: ",
      Integer.to_string(id),
      "\n",
      "event: completion.delta\n",
      build_data_lines(id),
      "\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp build_data_lines(id) do
    for part <- 1..@data_lines_per_event do
      [
        "data: {\"id\":",
        Integer.to_string(id),
        ",\"part\":",
        Integer.to_string(part),
        ",\"content\":\"",
        @data_chunk,
        "\"}\n"
      ]
    end
  end

  defp parse_complete!(input) do
    case Parser.parse(input.complete_payload) do
      {events, %Parser{event: nil, key: nil, value: nil}} ->
        if length(events) == input.complete_event_count do
          events
        else
          raise """
          unexpected result for complete payload:
          events=#{length(events)} expected=#{input.complete_event_count}
          """
        end

      {events, state} ->
        raise """
        unexpected parser state for complete payload:
        state=#{inspect(state)}
        events=#{length(events)} expected=#{input.complete_event_count}
        """
    end
  end

  defp parse_incomplete!(input) do
    {events, state} = Parser.parse(input.incomplete_payload)

    if length(events) == input.incomplete_complete_event_count and incomplete?(state) do
      {events, state}
    else
      raise """
      unexpected result for incomplete payload:
      events=#{length(events)} expected=#{input.incomplete_complete_event_count}
      state=#{inspect(state)}
      """
    end
  end

  defp incomplete?(%Parser{event: nil, key: nil, value: nil}), do: false
  defp incomplete?(%Parser{}), do: true

  defp print_inputs(inputs) do
    IO.puts("Benchmarking ServerSentEvents.Parser.parse/1")

    Enum.each(inputs, fn {label, input} ->
      IO.puts([
        "  ",
        label,
        ": complete=",
        format_bytes(byte_size(input.complete_payload)),
        " (",
        Integer.to_string(input.complete_event_count),
        " events), incomplete=",
        format_bytes(byte_size(input.incomplete_payload)),
        " (",
        Integer.to_string(input.incomplete_complete_event_count),
        " complete + ",
        format_bytes(input.incomplete_rest_bytes),
        " buffered)"
      ])
    end)

    IO.puts("")
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    :io_lib.format("~.2f MB", [bytes / 1_048_576]) |> IO.iodata_to_binary()
  end

  defp format_bytes(bytes) when bytes >= 1024 do
    :io_lib.format("~.2f KB", [bytes / 1024]) |> IO.iodata_to_binary()
  end

  defp format_bytes(bytes) do
    "#{bytes} B"
  end
end

ServerSentEvents.Bench.run()
