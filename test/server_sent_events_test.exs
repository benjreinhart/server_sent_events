defmodule ServerSentEventsTest do
  use ExUnit.Case, async: true

  test "basic example" do
    stream = """
    id: 1234
    event: event
    data: some data
    retry: 5000

    event:another_event
    data: some more data
    unknown: ignored

    event: stopping
    data: [DONE]

    """

    {%ServerSentEvents{}, events} = ServerSentEvents.parse(stream)

    assert events == [
             %{id: "1234", event: "event", data: "some data", retry: "5000"},
             %{event: "another_event", data: "some more data"},
             %{event: "stopping", data: "[DONE]"}
           ]
  end

  test "basic incomplete event" do
    chunk = """
    id: 1234
    event: event
    """

    {state, []} = ServerSentEvents.parse(chunk)

    chunk = """
    data: some data
    retry: 5000
    """

    {state, []} = ServerSentEvents.parse(state, chunk)

    chunk = "\n"

    {%ServerSentEvents{}, events} = ServerSentEvents.parse(state, chunk)

    assert events == [%{id: "1234", event: "event", data: "some data", retry: "5000"}]
  end

  test "empty stream" do
    {state, []} = ServerSentEvents.parse("")
    {state, []} = ServerSentEvents.parse(state, "")
    {state, []} = ServerSentEvents.parse(state, "\n")
    {state, []} = ServerSentEvents.parse(state, "\n")
    {%ServerSentEvents{}, []} = ServerSentEvents.parse(state, "")
  end

  test "ignores leading BOM" do
    stream = <<0xFEFF::utf8, "data: some data\n\n">>
    {%ServerSentEvents{}, events} = ServerSentEvents.parse(stream)
    assert events == [%{data: "some data"}]
  end

  test "does not ignore BOM when placed elsewhere" do
    {state, []} = ServerSentEvents.parse("event: bom\ndata:")

    {%ServerSentEvents{}, [event]} =
      ServerSentEvents.parse(state, <<0xFEFF::utf8, "post bom\n\n">>)

    assert event == %{event: "bom", data: <<0xFEFF::utf8, "post bom">>}
  end

  test "supports incomplete keys and values" do
    {state, []} = ServerSentEvents.parse("i")
    {state, []} = ServerSentEvents.parse(state, "d")
    {state, []} = ServerSentEvents.parse(state, ": va")
    {state, []} = ServerSentEvents.parse(state, "lue")
    {state, []} = ServerSentEvents.parse(state, "\n")
    {state, []} = ServerSentEvents.parse(state, "dat")
    {state, []} = ServerSentEvents.parse(state, "a: some ")
    {state, []} = ServerSentEvents.parse(state, "other value\n")
    {%ServerSentEvents{}, [event]} = ServerSentEvents.parse(state, "\n")

    assert event == %{id: "value", data: "some other value"}
  end

  describe "line separators" do
    test "LF separates lines" do
      {%ServerSentEvents{}, events} = ServerSentEvents.parse("event: foo\ndata: bar\n\n")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "CRLF separates lines" do
      {%ServerSentEvents{}, events} = ServerSentEvents.parse("event: foo\r\ndata: bar\r\n\r\n")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "CR separates lines" do
      {%ServerSentEvents{}, events} = ServerSentEvents.parse("event: foo\rdata: bar\r\r")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "handles CRLF split across chunks" do
      {state, []} = ServerSentEvents.parse("event: foo\r\ndata: bar\r")
      {state, []} = ServerSentEvents.parse(state, "\n")
      {state, events} = ServerSentEvents.parse(state, "\r")
      assert events == [%{event: "foo", data: "bar"}]
      {%ServerSentEvents{}, []} = ServerSentEvents.parse(state, "\n")
    end

    test "handles CR split across chunks" do
      {state, []} = ServerSentEvents.parse("event: foo\rdata: bar\r")
      {state, []} = ServerSentEvents.parse(state, "retry: 1000\r")
      {%ServerSentEvents{}, events} = ServerSentEvents.parse(state, "\r")
      assert events == [%{event: "foo", data: "bar", retry: "1000"}]
    end

    test "when eof before finalizing event with CR" do
      {state, []} = ServerSentEvents.parse("event: foo")
      {state, []} = ServerSentEvents.parse(state, "\r")
      {%ServerSentEvents{}, events} = ServerSentEvents.parse(state, "\r")
      assert events == [%{event: "foo"}]
    end

    test "mix and match line separators" do
      {%ServerSentEvents{}, events} = ServerSentEvents.parse("id: 1\revent: foo\ndata: bar\r\n\n")
      assert events == [%{id: "1", event: "foo", data: "bar"}]
    end
  end

  describe "empty values" do
    test "handles empty values" do
      {%ServerSentEvents{}, events} = ServerSentEvents.parse("event:\ndata:\n\n")
      assert events == [%{event: "", data: ""}]
    end
  end

  describe "keys" do
    test "incomplete keys" do
      {state, []} = ServerSentEvents.parse("e")
      {state, []} = ServerSentEvents.parse(state, "v")
      {state, []} = ServerSentEvents.parse(state, "ent: foo\n")
      {state, []} = ServerSentEvents.parse(state, "d")
      {%ServerSentEvents{}, events} = ServerSentEvents.parse(state, "ata: bar\n\n")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "keys with no value" do
      {%ServerSentEvents{}, events} = ServerSentEvents.parse("event\ndata: value\n\n")
      assert events == [%{event: "", data: "value"}]
    end

    test "repeated id, event, and retry keys will overwrite their previous value" do
      {%ServerSentEvents{}, events} = ServerSentEvents.parse("event: foo\nevent: bar\n\n")
      assert events == [%{event: "bar"}]

      {%ServerSentEvents{}, events} = ServerSentEvents.parse("id: 1\nid: 2\n\n")
      assert events == [%{id: "2"}]

      {%ServerSentEvents{}, events} = ServerSentEvents.parse("retry: 1000\nretry: 2000\n\n")
      assert events == [%{retry: "2000"}]
    end

    test "ignores unrecognized keys" do
      {%ServerSentEvents{}, []} = ServerSentEvents.parse("unknown: value\n\n")

      {%ServerSentEvents{}, [event]} =
        ServerSentEvents.parse("event: foo\nunknown: value\ndata: bar\n\n")

      assert event == %{event: "foo", data: "bar"}
    end

    test "ignores unreognized keys with no value" do
      {%ServerSentEvents{}, []} = ServerSentEvents.parse("unknown\n\n")

      {%ServerSentEvents{}, [event]} =
        ServerSentEvents.parse("event: foo\nunknown\nid: 1234\n\n")

      assert event == %{event: "foo", id: "1234"}
    end
  end

  describe "values" do
    test "a single leading space is ignored" do
      {%ServerSentEvents{}, [%{id: "id"}]} = ServerSentEvents.parse("id:id\n\n")
      {%ServerSentEvents{}, [%{id: "id"}]} = ServerSentEvents.parse("id: id\n\n")
      {%ServerSentEvents{}, [%{id: " id"}]} = ServerSentEvents.parse("id:  id\n\n")

      {%ServerSentEvents{}, [%{event: "event"}]} = ServerSentEvents.parse("event:event\n\n")
      {%ServerSentEvents{}, [%{event: "event"}]} = ServerSentEvents.parse("event: event\n\n")
      {%ServerSentEvents{}, [%{event: " event"}]} = ServerSentEvents.parse("event:  event\n\n")

      {%ServerSentEvents{}, [%{data: "data"}]} = ServerSentEvents.parse("data:data\n\n")
      {%ServerSentEvents{}, [%{data: "data"}]} = ServerSentEvents.parse("data: data\n\n")
      {%ServerSentEvents{}, [%{data: " data"}]} = ServerSentEvents.parse("data:  data\n\n")

      {%ServerSentEvents{}, [%{retry: "retry"}]} = ServerSentEvents.parse("retry:retry\n\n")
      {%ServerSentEvents{}, [%{retry: "retry"}]} = ServerSentEvents.parse("retry: retry\n\n")
      {%ServerSentEvents{}, [%{retry: " retry"}]} = ServerSentEvents.parse("retry:  retry\n\n")
    end

    test "a single leading space is still ignored when chunked" do
      {state, []} = ServerSentEvents.parse("event:")
      {state, []} = ServerSentEvents.parse(state, " ")
      {%ServerSentEvents{}, [%{event: "event"}]} = ServerSentEvents.parse(state, "event\n\n")

      {state, []} = ServerSentEvents.parse("event:")
      {state, []} = ServerSentEvents.parse(state, " ")
      {%ServerSentEvents{}, [%{event: " event"}]} = ServerSentEvents.parse(state, " event\n\n")
    end
  end

  describe "data" do
    test "multiple data lines are concatenated with newlines" do
      {%ServerSentEvents{}, events} =
        ServerSentEvents.parse("data: line 1\ndata: line 2\ndata: line 3\n\n")

      assert events == [%{data: "line 1\nline 2\nline 3"}]
    end

    test "multiple data lines arriving in incomplete chunks are still concatenated with newlines" do
      {state, []} = ServerSentEvents.parse("event: data_")
      {state, []} = ServerSentEvents.parse(state, "test\nda")
      {state, []} = ServerSentEvents.parse(state, "ta")
      {state, []} = ServerSentEvents.parse(state, ": lin")
      {state, []} = ServerSentEvents.parse(state, "e 1")
      {state, []} = ServerSentEvents.parse(state, "\ndata: ")
      {state, []} = ServerSentEvents.parse(state, "line 2")
      {state, []} = ServerSentEvents.parse(state, "\ndata: line 3\n")
      {%ServerSentEvents{}, events} = ServerSentEvents.parse(state, "\n")

      assert events == [%{event: "data_test", data: "line 1\nline 2\nline 3"}]
    end
  end

  describe "comments" do
    test "allows comments but ignores them" do
      # Standalone comment
      {%ServerSentEvents{}, []} = ServerSentEvents.parse(": this is a comment\n\n")

      # Standalone comment followed by event
      {%ServerSentEvents{}, [event]} =
        ServerSentEvents.parse(": this is a comment\n\nid: 1\nevent:foo\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with leading comment
      {%ServerSentEvents{}, [event]} =
        ServerSentEvents.parse(": this is a comment\nid: 1\nevent:foo\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with comment inside it
      {%ServerSentEvents{}, [event]} =
        ServerSentEvents.parse("id: 1\nevent:foo\n: this is a comment\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with trailing comment
      {%ServerSentEvents{}, [event]} =
        ServerSentEvents.parse("id: 1\nevent:foo\ndata: bar\n: this is a comment\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event followed by a standalone comment
      {%ServerSentEvents{}, [event]} =
        ServerSentEvents.parse("id: 1\nevent:foo\ndata: bar\n\n: this is a comment\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # comment in a comment line is still a comment
      {%ServerSentEvents{}, []} = ServerSentEvents.parse(": this is a comment: with a colon\n\n")
    end

    test "allows comments but ignores them when split across chunks" do
      {state, []} = ServerSentEvents.parse("")
      {state, []} = ServerSentEvents.parse(state, ": ")
      {state, []} = ServerSentEvents.parse(state, "comments begin with a colon: '")
      {state, []} = ServerSentEvents.parse(state, ": this is a comment'\n")
      {state, []} = ServerSentEvents.parse(state, "\n")
      {%ServerSentEvents{}, []} = ServerSentEvents.parse(state, "")
    end
  end
end
