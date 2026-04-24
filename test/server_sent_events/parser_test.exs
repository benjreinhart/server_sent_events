defmodule ServerSentEvents.ParserTest do
  use ExUnit.Case, async: true

  alias ServerSentEvents.Parser

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

    {%Parser{}, events} = Parser.parse(stream)

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

    {state, []} = Parser.parse(chunk)

    chunk = """
    data: some data
    retry: 5000
    """

    {state, []} = Parser.parse(state, chunk)

    chunk = "\n"

    {%Parser{}, events} = Parser.parse(state, chunk)

    assert events == [%{id: "1234", event: "event", data: "some data", retry: "5000"}]
  end

  test "empty stream" do
    {state, []} = Parser.parse("")
    {state, []} = Parser.parse(state, "")
    {state, []} = Parser.parse(state, "\n")
    {state, []} = Parser.parse(state, "\n")
    {%Parser{}, []} = Parser.parse(state, "")
  end

  test "ignores leading BOM" do
    stream = <<0xFEFF::utf8, "data: some data\n\n">>
    {%Parser{}, events} = Parser.parse(stream)
    assert events == [%{data: "some data"}]
  end

  test "does not ignore BOM when placed elsewhere" do
    {state, []} = Parser.parse("event: bom\ndata:")

    {%Parser{}, [event]} =
      Parser.parse(state, <<0xFEFF::utf8, "post bom\n\n">>)

    assert event == %{event: "bom", data: <<0xFEFF::utf8, "post bom">>}
  end

  test "supports incomplete keys and values" do
    {state, []} = Parser.parse("i")
    {state, []} = Parser.parse(state, "d")
    {state, []} = Parser.parse(state, ": va")
    {state, []} = Parser.parse(state, "lue")
    {state, []} = Parser.parse(state, "\n")
    {state, []} = Parser.parse(state, "dat")
    {state, []} = Parser.parse(state, "a: some ")
    {state, []} = Parser.parse(state, "other value\n")
    {%Parser{}, [event]} = Parser.parse(state, "\n")

    assert event == %{id: "value", data: "some other value"}
  end

  describe "line separators" do
    test "LF separates lines" do
      {%Parser{}, events} = Parser.parse("event: foo\ndata: bar\n\n")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "CRLF separates lines" do
      {%Parser{}, events} = Parser.parse("event: foo\r\ndata: bar\r\n\r\n")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "CR separates lines" do
      {%Parser{}, events} = Parser.parse("event: foo\rdata: bar\r\r")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "handles CRLF split across chunks" do
      {state, []} = Parser.parse("event: foo\r\ndata: bar\r")
      {state, []} = Parser.parse(state, "\n")
      {state, events} = Parser.parse(state, "\r")
      assert events == [%{event: "foo", data: "bar"}]
      {%Parser{}, []} = Parser.parse(state, "\n")
    end

    test "handles CR split across chunks" do
      {state, []} = Parser.parse("event: foo\rdata: bar\r")
      {state, []} = Parser.parse(state, "retry: 1000\r")
      {%Parser{}, events} = Parser.parse(state, "\r")
      assert events == [%{event: "foo", data: "bar", retry: "1000"}]
    end

    test "when eof before finalizing event with CR" do
      {state, []} = Parser.parse("event: foo")
      {state, []} = Parser.parse(state, "\r")
      {%Parser{}, events} = Parser.parse(state, "\r")
      assert events == [%{event: "foo"}]
    end

    test "mix and match line separators" do
      {%Parser{}, events} = Parser.parse("id: 1\revent: foo\ndata: bar\r\n\n")
      assert events == [%{id: "1", event: "foo", data: "bar"}]
    end
  end

  describe "empty values" do
    test "handles empty values" do
      {%Parser{}, events} = Parser.parse("event:\ndata:\n\n")
      assert events == [%{event: "", data: ""}]
    end
  end

  describe "keys" do
    test "incomplete keys" do
      {state, []} = Parser.parse("e")
      {state, []} = Parser.parse(state, "v")
      {state, []} = Parser.parse(state, "ent: foo\n")
      {state, []} = Parser.parse(state, "d")
      {%Parser{}, events} = Parser.parse(state, "ata: bar\n\n")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "keys with no value" do
      {%Parser{}, events} = Parser.parse("event\ndata: value\n\n")
      assert events == [%{event: "", data: "value"}]
    end

    test "repeated id, event, and retry keys will overwrite their previous value" do
      {%Parser{}, events} = Parser.parse("event: foo\nevent: bar\n\n")
      assert events == [%{event: "bar"}]

      {%Parser{}, events} = Parser.parse("id: 1\nid: 2\n\n")
      assert events == [%{id: "2"}]

      {%Parser{}, events} = Parser.parse("retry: 1000\nretry: 2000\n\n")
      assert events == [%{retry: "2000"}]
    end

    test "ignores unrecognized keys" do
      {%Parser{}, []} = Parser.parse("unknown: value\n\n")

      {%Parser{}, [event]} =
        Parser.parse("event: foo\nunknown: value\ndata: bar\n\n")

      assert event == %{event: "foo", data: "bar"}
    end

    test "ignores unreognized keys with no value" do
      {%Parser{}, []} = Parser.parse("unknown\n\n")

      {%Parser{}, [event]} =
        Parser.parse("event: foo\nunknown\nid: 1234\n\n")

      assert event == %{event: "foo", id: "1234"}
    end
  end

  describe "values" do
    test "a single leading space is ignored" do
      {%Parser{}, [%{id: "id"}]} = Parser.parse("id:id\n\n")
      {%Parser{}, [%{id: "id"}]} = Parser.parse("id: id\n\n")
      {%Parser{}, [%{id: " id"}]} = Parser.parse("id:  id\n\n")

      {%Parser{}, [%{event: "event"}]} = Parser.parse("event:event\n\n")
      {%Parser{}, [%{event: "event"}]} = Parser.parse("event: event\n\n")
      {%Parser{}, [%{event: " event"}]} = Parser.parse("event:  event\n\n")

      {%Parser{}, [%{data: "data"}]} = Parser.parse("data:data\n\n")
      {%Parser{}, [%{data: "data"}]} = Parser.parse("data: data\n\n")
      {%Parser{}, [%{data: " data"}]} = Parser.parse("data:  data\n\n")

      {%Parser{}, [%{retry: "retry"}]} = Parser.parse("retry:retry\n\n")
      {%Parser{}, [%{retry: "retry"}]} = Parser.parse("retry: retry\n\n")
      {%Parser{}, [%{retry: " retry"}]} = Parser.parse("retry:  retry\n\n")
    end

    test "a single leading space is still ignored when chunked" do
      {state, []} = Parser.parse("event:")
      {state, []} = Parser.parse(state, " ")
      {%Parser{}, [%{event: "event"}]} = Parser.parse(state, "event\n\n")

      {state, []} = Parser.parse("event:")
      {state, []} = Parser.parse(state, " ")
      {%Parser{}, [%{event: " event"}]} = Parser.parse(state, " event\n\n")
    end
  end

  describe "data" do
    test "multiple data lines are concatenated with newlines" do
      {%Parser{}, events} =
        Parser.parse("data: line 1\ndata: line 2\ndata: line 3\n\n")

      assert events == [%{data: "line 1\nline 2\nline 3"}]
    end

    test "multiple data lines arriving in incomplete chunks are still concatenated with newlines" do
      {state, []} = Parser.parse("event: data_")
      {state, []} = Parser.parse(state, "test\nda")
      {state, []} = Parser.parse(state, "ta")
      {state, []} = Parser.parse(state, ": lin")
      {state, []} = Parser.parse(state, "e 1")
      {state, []} = Parser.parse(state, "\ndata: ")
      {state, []} = Parser.parse(state, "line 2")
      {state, []} = Parser.parse(state, "\ndata: line 3\n")
      {%Parser{}, events} = Parser.parse(state, "\n")

      assert events == [%{event: "data_test", data: "line 1\nline 2\nline 3"}]
    end
  end

  describe "comments" do
    test "allows comments but ignores them" do
      # Standalone comment
      {%Parser{}, []} = Parser.parse(": this is a comment\n\n")

      # Standalone comment followed by event
      {%Parser{}, [event]} =
        Parser.parse(": this is a comment\n\nid: 1\nevent:foo\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with leading comment
      {%Parser{}, [event]} =
        Parser.parse(": this is a comment\nid: 1\nevent:foo\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with comment inside it
      {%Parser{}, [event]} =
        Parser.parse("id: 1\nevent:foo\n: this is a comment\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with trailing comment
      {%Parser{}, [event]} =
        Parser.parse("id: 1\nevent:foo\ndata: bar\n: this is a comment\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event followed by a standalone comment
      {%Parser{}, [event]} =
        Parser.parse("id: 1\nevent:foo\ndata: bar\n\n: this is a comment\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # comment in a comment line is still a comment
      {%Parser{}, []} = Parser.parse(": this is a comment: with a colon\n\n")
    end

    test "allows comments but ignores them when split across chunks" do
      {state, []} = Parser.parse("")
      {state, []} = Parser.parse(state, ": ")
      {state, []} = Parser.parse(state, "comments begin with a colon: '")
      {state, []} = Parser.parse(state, ": this is a comment'\n")
      {state, []} = Parser.parse(state, "\n")
      {%Parser{}, []} = Parser.parse(state, "")
    end
  end
end
