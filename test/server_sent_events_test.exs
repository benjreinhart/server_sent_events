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
end
