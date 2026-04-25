defmodule ServerSentEventsTest do
  use ExUnit.Case, async: true

  doctest ServerSentEvents

  test "parses an enumerable of chunks into events" do
    chunks = [
      "event: first\n",
      "data: one\n\n",
      "event: second\n",
      "data: two\n\n"
    ]

    events = chunks |> ServerSentEvents.parse() |> Enum.to_list()

    assert events == [
             %{event: "first", data: "one"},
             %{event: "second", data: "two"}
           ]
  end

  test "preserves parser state across chunk boundaries" do
    chunks = [
      "event: fir",
      "st\ndata: o",
      "ne\n\nevent: second\ndata:",
      " two\n\n"
    ]

    events = chunks |> ServerSentEvents.parse() |> Enum.to_list()

    assert events == [
             %{event: "first", data: "one"},
             %{event: "second", data: "two"}
           ]
  end

  test "does not emit incomplete trailing events" do
    chunks = [
      "event: complete\ndata: one\n\n",
      "event: incomplete\ndata: two"
    ]

    events = chunks |> ServerSentEvents.parse() |> Enum.to_list()

    assert events == [%{event: "complete", data: "one"}]
  end
end
