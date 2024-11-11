defmodule ServerSentEventsTest do
  use ExUnit.Case, async: true
  doctest ServerSentEvents

  test "parse basic server sent events" do
    data = """
    event: starting
    data: {"status":"starting","progress":0}

    event: updating
    data: {"status":"processing","progress":45}

    event: updating
    data: {"status":"still_processing","progress":98}

    event: finishing
    data: [DONE]

    """

    {events, rest} = ServerSentEvents.parse(data)

    assert rest == ""

    assert events == [
             %{
               "event" => "starting",
               "data" => "{\"status\":\"starting\",\"progress\":0}"
             },
             %{
               "event" => "updating",
               "data" => "{\"status\":\"processing\",\"progress\":45}"
             },
             %{
               "event" => "updating",
               "data" => "{\"status\":\"still_processing\",\"progress\":98}"
             },
             %{
               "event" => "finishing",
               "data" => "[DONE]"
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

  test "parser ignores empty events" do
    {events, rest} = ServerSentEvents.parse("\n\n\r\n\r\n\n\n")

    assert rest == ""
    assert events == []
  end

  test "space after colon is optional" do
    {events, rest} = ServerSentEvents.parse("event:event_type\ndata:data\n\n")

    assert rest == ""
    assert events == [%{"event" => "event_type", "data" => "data"}]
  end

  test "strips exactly on leading space after colon but no more" do
    {events, rest} = ServerSentEvents.parse("event:  event_type\ndata:  data\n\n")

    assert rest == ""
    assert events == [%{"event" => " event_type", "data" => " data"}]
  end

  test "colon is optional" do
    {events, rest} = ServerSentEvents.parse("event\n\n")

    assert rest == ""
    assert events == [%{"event" => ""}]

    {events, rest} = ServerSentEvents.parse("data\n\n")

    assert rest == ""
    assert events == [%{"data" => ""}]
  end

  test "parser ignores comments" do
    {events, rest} =
      ServerSentEvents.parse(
        ": this is a comment\n\nevent: name\ndata: data\n\n: this is a comment\n\n"
      )

    assert rest == ""
    assert events == [%{"event" => "name", "data" => "data"}]
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
    assert events == [%{"event" => "event_name", "data" => "foo bar"}]
  end

  test "parse data that spans multiple lines" do
    {events, rest} = ServerSentEvents.parse("event: multi\ndata: foo\ndata: bar\ndata: baz\n\n")

    assert rest == ""
    assert events == [%{"event" => "multi", "data" => "foo\nbar\nbaz"}]
  end

  test "uses last event as the event type when multiple are specified" do
    {events, rest} =
      ServerSentEvents.parse("event: event1\nevent: event2\nevent: event3\ndata: data\n\n")

    assert rest == ""
    assert events == [%{"event" => "event3", "data" => "data"}]
  end

  test "empty event resets non-empty event when it follows non-empty event" do
    {events, rest} =
      ServerSentEvents.parse("event: event1\nevent\ndata: data\n\n")

    assert rest == ""
    assert events == [%{"event" => "", "data" => "data"}]

    {events, rest} =
      ServerSentEvents.parse("event: event1\nevent:\ndata: data\n\n")

    assert rest == ""
    assert events == [%{"event" => "", "data" => "data"}]
  end

  test "parses empty data" do
    {events, rest} = ServerSentEvents.parse("data\n\ndata\ndata\n\ndata:\n")

    assert rest == "data:\n"
    assert events == [%{"data" => ""}, %{"data" => "\n"}]

    {events, rest} = ServerSentEvents.parse("data\r\n\r\ndata\r\ndata\r\n\r\ndata:\r\n")

    assert rest == "data:\r\n"
    assert events == [%{"data" => ""}, %{"data" => "\n"}]

    {events, rest} = ServerSentEvents.parse("data\r\rdata\rdata\r\rdata:\r")

    assert rest == "data:\r"
    assert events == [%{"data" => ""}, %{"data" => "\n"}]
  end

  test "parse recognizes different line separators" do
    {events, rest} = ServerSentEvents.parse("event: event_name\r\ndata: data\r\n\r\n")

    assert rest == ""
    assert events == [%{"event" => "event_name", "data" => "data"}]

    {events, rest} = ServerSentEvents.parse("event: event_name\rdata: data\r\r")

    assert rest == ""
    assert events == [%{"event" => "event_name", "data" => "data"}]
  end

  test "handles multibyte characters" do
    {events, rest} = ServerSentEvents.parse("event: €豆腐\ndata: 我現在都看實況不玩遊戲\n\n")

    assert rest == ""
    assert events == [%{"event" => "€豆腐", "data" => "我現在都看實況不玩遊戲"}]

    {events, rest} = ServerSentEvents.parse("event: 👋\ndata: Hello 🔥\n\n")

    assert rest == ""
    assert events == [%{"event" => "👋", "data" => "Hello 🔥"}]
  end

  test "handles split multibyte characters" do
    # The '🚀' emoji is 4 bytes. Here we split the string in the middle of the emoji
    # to test that the parser can handle incomplete chunks where the end of one chunk
    # falls in the middle of a multibyte character.
    <<first_chunk::bytes-size(8), second_chunk::bytes-size(4)>> = "data: 🚀\n\n"

    {[], ^first_chunk} = ServerSentEvents.parse(first_chunk)
    {events, rest} = ServerSentEvents.parse(first_chunk <> second_chunk)

    assert rest == ""
    assert events == [%{"data" => "🚀"}]
  end

  test "parses retry event" do
    {events, rest} = ServerSentEvents.parse("retry: 10000\n\n")

    assert rest == ""
    assert events == [%{"retry" => 10000}]
  end

  test "ignores retry when value is not ascii digits" do
    {events, rest} = ServerSentEvents.parse("retry: abc\n\n")

    assert rest == ""
    assert events == []
  end

  test "ignores non-recognized event fields" do
    {events, rest} = ServerSentEvents.parse("unknown: value\n\n")

    assert rest == ""
    assert events == []

    {events, rest} = ServerSentEvents.parse("unknown\n\n")

    assert rest == ""
    assert events == []

    {events, rest} = ServerSentEvents.parse(" :\n\n")

    assert rest == ""
    assert events == []

    {events, rest} = ServerSentEvents.parse(" \n\n")

    assert rest == ""
    assert events == []

    {events, rest} = ServerSentEvents.parse("unknown\ndata: data\n\n")

    assert rest == ""
    assert events == [%{"data" => "data"}]
  end
end
