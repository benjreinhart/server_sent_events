defmodule ServerSentEventsTest do
  use ExUnit.Case, async: true
  doctest ServerSentEvents

  test "parse basic server sent events" do
    data = """
    event: starting
    data: {"status": "starting", "progress": 0}

    event: updating
    data: {"status": "processing", "progress": 45}

    event: updating
    data: {"status": "still_processing", "progress": 98}

    event: finishing
    data: [DONE]

    """

    {events, rest} = ServerSentEvents.parse(data)

    assert rest == ""

    assert events == [
             %{
               "event" => "starting",
               "data" => "{\"status\": \"starting\", \"progress\": 0}\n"
             },
             %{
               "event" => "updating",
               "data" => "{\"status\": \"processing\", \"progress\": 45}\n"
             },
             %{
               "event" => "updating",
               "data" => "{\"status\": \"still_processing\", \"progress\": 98}\n"
             },
             %{
               "event" => "finishing",
               "data" => "[DONE]\n"
             }
           ]
  end

  test "ignores BOM" do
    {events, rest} = ServerSentEvents.parse(<<0xEF, 0xBB, 0xBF>>)

    assert rest == ""
    assert events == []
  end

  test "parse with empty string" do
    {events, rest} = ServerSentEvents.parse("")

    assert rest == ""
    assert events == []
  end

  test "parser ignores comments" do
    {events, rest} =
      ServerSentEvents.parse(
        ": this is a comment\n\nevent: name\ndata: data\n\n: this is a comment\n\n"
      )

    assert rest == ""
    assert events == [%{"event" => "name", "data" => "data\n"}]
  end

  test "parse incomplete" do
    {events, rest} = ServerSentEvents.parse("event: event_name\n")

    assert rest == "event: event_name\n"
    assert events == []

    {events, rest} = ServerSentEvents.parse("event: event_name\ndata: foo")

    assert rest == "event: event_name\ndata: foo"
    assert events == []

    {events, rest} = ServerSentEvents.parse("event: event_name\ndata: foo bar\n\n")

    assert rest == ""
    assert events == [%{"data" => "foo bar\n", "event" => "event_name"}]
  end

  test "parse data that spans multiple lines" do
    {events, rest} = ServerSentEvents.parse("event: multi\ndata: foo\ndata: bar\ndata: baz\n\n")

    assert rest == ""
    assert events == [%{"event" => "multi", "data" => "foo\nbar\nbaz\n"}]
  end

  test "parse recognizes different line separators" do
    {events, rest} = ServerSentEvents.parse("event: event_name\r\ndata: data\r\n\r\n")

    assert rest == ""
    assert events == [%{"data" => "data\n", "event" => "event_name"}]

    {events, rest} = ServerSentEvents.parse("event: event_name\rdata: data\r\r")

    assert rest == ""
    assert events == [%{"data" => "data\n", "event" => "event_name"}]
  end
end
