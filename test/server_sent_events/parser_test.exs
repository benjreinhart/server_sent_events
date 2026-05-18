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

    {events, %Parser{}} = Parser.parse(stream)

    assert events == [
             %{id: "1234", event: "event", data: "some data", retry: 5000},
             %{event: "another_event", data: "some more data"},
             %{event: "stopping", data: "[DONE]"}
           ]
  end

  test "basic incomplete event" do
    chunk = """
    id: 1234
    event: event
    """

    {[], state} = Parser.parse(chunk)

    chunk = """
    data: some data
    retry: 5000
    """

    {[], state} = Parser.parse(state, chunk)

    chunk = "\n"

    {events, %Parser{}} = Parser.parse(state, chunk)

    assert events == [%{id: "1234", event: "event", data: "some data", retry: 5000}]
  end

  test "empty stream" do
    {[], state} = Parser.parse("")
    {[], state} = Parser.parse(state, "")
    {[], state} = Parser.parse(state, "\n")
    {[], state} = Parser.parse(state, "\n")
    {[], %Parser{}} = Parser.parse(state, "")
  end

  test "ignores leading BOM" do
    stream = <<0xFEFF::utf8, "data: some data\n\n">>
    {events, %Parser{}} = Parser.parse(stream)
    assert events == [%{data: "some data"}]
  end

  test "does not ignore BOM when placed elsewhere" do
    {[], state} = Parser.parse("event: bom\ndata:")

    {[event], %Parser{}} =
      Parser.parse(state, <<0xFEFF::utf8, "post bom\n\n">>)

    assert event == %{event: "bom", data: <<0xFEFF::utf8, "post bom">>}
  end

  test "preserves multi-byte UTF-8 characters in field values" do
    id = "事件-☃"
    event = "résumé"
    data = "café こんにちは 👋"

    {events, %Parser{}} = Parser.parse("id: #{id}\nevent: #{event}\ndata: #{data}\n\n")

    assert events == [%{id: id, event: event, data: data}]
  end

  test "preserves multi-byte UTF-8 characters split across chunks" do
    <<b1, b2, b3, b4>> = "👋"

    first_half = <<b1, b2>>
    second_half = <<b3, b4>>

    {[], state} = Parser.parse("event: hello\ndata")
    {[], state} = Parser.parse(state, ": " <> first_half)
    {[event], %Parser{}} = Parser.parse(state, second_half <> "\n\n")

    assert event == %{event: "hello", data: "👋"}
  end

  test "preserves a grapheme split across chunks" do
    grapheme = "e" <> <<0xCC, 0x81>>
    assert String.length(grapheme) == 1

    {[], state} = Parser.parse("event: coffee\ndata")
    {[], state} = Parser.parse(state, ": cafe" <> <<0xCC>>)
    {[event], %Parser{}} = Parser.parse(state, <<0x81, "\n\n">>)

    assert event == %{event: "coffee", data: "café"}
  end

  test "supports incomplete keys and values" do
    {[], state} = Parser.parse("i")
    {[], state} = Parser.parse(state, "d")
    {[], state} = Parser.parse(state, ": va")
    {[], state} = Parser.parse(state, "lue")
    {[], state} = Parser.parse(state, "\n")
    {[], state} = Parser.parse(state, "dat")
    {[], state} = Parser.parse(state, "a: some ")
    {[], state} = Parser.parse(state, "other value\n")
    {[event], %Parser{}} = Parser.parse(state, "\n")

    assert event == %{id: "value", data: "some other value"}
  end

  describe "line separators" do
    test "LF separates lines" do
      {events, %Parser{}} = Parser.parse("event: foo\ndata: bar\n\n")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "CRLF separates lines" do
      {events, %Parser{}} = Parser.parse("event: foo\r\ndata: bar\r\n\r\n")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "CR separates lines" do
      {events, %Parser{}} = Parser.parse("event: foo\rdata: bar\r\r")
      assert events == [%{event: "foo", data: "bar"}]
    end

    test "handles CRLF split across chunks" do
      {[], state} = Parser.parse("event: foo\r\ndata: bar\r")
      {[], state} = Parser.parse(state, "\n")
      {[event], state} = Parser.parse(state, "\r")
      assert event == %{event: "foo", data: "bar"}
      {[], %Parser{}} = Parser.parse(state, "\n")
    end

    test "handles CR split across chunks" do
      {[], state} = Parser.parse("event: foo\rdata: bar\r")
      {[], state} = Parser.parse(state, "retry: 1000\r")
      {events, %Parser{}} = Parser.parse(state, "\r")
      assert events == [%{event: "foo", data: "bar", retry: 1000}]
    end

    test "when eof before finalizing event with CR" do
      {[], state} = Parser.parse("event: foo")
      {[], state} = Parser.parse(state, "\r")
      {events, %Parser{}} = Parser.parse(state, "\r")
      assert events == []
    end

    test "mix and match line separators" do
      {events, %Parser{}} = Parser.parse("id: 1\revent: foo\ndata: bar\r\n\n")
      assert events == [%{id: "1", event: "foo", data: "bar"}]
    end
  end

  describe "empty values" do
    test "handles empty values" do
      {events, %Parser{}} = Parser.parse("event:\ndata:\n\n")
      assert events == [%{event: "", data: ""}]
    end
  end

  test "incomplete keys" do
    {[], state} = Parser.parse("e")
    {[], state} = Parser.parse(state, "v")
    {[], state} = Parser.parse(state, "ent: foo\n")
    {[], state} = Parser.parse(state, "d")
    {events, %Parser{}} = Parser.parse(state, "ata: bar\n\n")
    assert events == [%{event: "foo", data: "bar"}]
  end

  test "keys with no value" do
    {events, %Parser{}} = Parser.parse("event\ndata: value\n\n")
    assert events == [%{event: "", data: "value"}]

    {events, %Parser{}} = Parser.parse("id\ndata: value\n\n")
    assert events == [%{id: "", data: "value"}]
  end

  test "repeated id, event, and retry keys will overwrite their previous value" do
    {events, %Parser{}} = Parser.parse("event: foo\nevent: bar\ndata: value\n\n")
    assert events == [%{event: "bar", data: "value"}]

    {events, %Parser{}} = Parser.parse("id: 1\nid: 2\ndata: value\n\n")
    assert events == [%{id: "2", data: "value"}]

    {events, %Parser{}} = Parser.parse("retry: 1000\nretry: 2000\ndata: value\n\n")
    assert events == [%{retry: 2000, data: "value"}]
  end

  test "suppresses events without data" do
    {events, %Parser{}} = Parser.parse("id: 1\nevent: foo\nretry: 1000\n\n")
    assert events == []

    {events, %Parser{}} = Parser.parse("id: 1\nevent: foo\nretry: 1000\ndata:\n\n")
    assert events == [%{id: "1", event: "foo", retry: 1000, data: ""}]
  end

  test "ignores unrecognized keys" do
    {[], %Parser{}} = Parser.parse("unknown: value\n\n")

    {[event], %Parser{}} =
      Parser.parse("event: foo\nunknown: value\ndata: bar\n\n")

    assert event == %{event: "foo", data: "bar"}
  end

  test "ignores unreognized keys with no value" do
    {[], %Parser{}} = Parser.parse("unknown\n\n")

    {[event], %Parser{}} =
      Parser.parse("event: foo\nunknown\nid: 1234\ndata: value\n\n")

    assert event == %{event: "foo", id: "1234", data: "value"}
  end

  test "a single leading space is ignored" do
    {[%{id: "id", data: "value"}], %Parser{}} = Parser.parse("id:id\ndata: value\n\n")
    {[%{id: "id", data: "value"}], %Parser{}} = Parser.parse("id: id\ndata: value\n\n")
    {[%{id: " id", data: "value"}], %Parser{}} = Parser.parse("id:  id\ndata: value\n\n")

    {[%{event: "event", data: "value"}], %Parser{}} =
      Parser.parse("event:event\ndata: value\n\n")

    {[%{event: "event", data: "value"}], %Parser{}} =
      Parser.parse("event: event\ndata: value\n\n")

    {[%{event: " event", data: "value"}], %Parser{}} =
      Parser.parse("event:  event\ndata: value\n\n")

    {[%{data: "data"}], %Parser{}} = Parser.parse("data:data\n\n")
    {[%{data: "data"}], %Parser{}} = Parser.parse("data: data\n\n")
    {[%{data: " data"}], %Parser{}} = Parser.parse("data:  data\n\n")

    {[%{retry: 1000, data: "value"}], %Parser{}} = Parser.parse("retry:1000\ndata: value\n\n")
    {[%{retry: 1000, data: "value"}], %Parser{}} = Parser.parse("retry: 1000\ndata: value\n\n")
    # Retry contains space here, which makes in invalid and thus ignored.
    {[%{data: "value"}], %Parser{}} = Parser.parse("retry:  1000\ndata: value\n\n")
  end

  test "a single leading space is still ignored when chunked" do
    {[], state} = Parser.parse("event:")
    {[], state} = Parser.parse(state, " ")

    {[%{event: "event", data: "value"}], %Parser{}} =
      Parser.parse(state, "event\ndata: value\n\n")

    {[], state} = Parser.parse("event:")
    {[], state} = Parser.parse(state, " ")

    {[%{event: " event", data: "value"}], %Parser{}} =
      Parser.parse(state, " event\ndata: value\n\n")
  end

  test "retry fields must contain only ASCII digits" do
    {events, %Parser{}} = Parser.parse("retry: 1000\nretry: 10ms\ndata: value\n\n")
    assert events == [%{retry: 1000, data: "value"}]

    non_ascii_digit = <<0xD9, 0xA1>>

    {events, %Parser{}} =
      Parser.parse(
        "retry:\nretry: -1\nretry: 1.5\nretry: " <> non_ascii_digit <> "\ndata: value\n\n"
      )

    assert events == [%{data: "value"}]
  end

  test "id fields containing NULL are ignored" do
    {events, %Parser{}} = Parser.parse("id: 1\nid: a\0b\ndata: value\n\n")
    assert events == [%{id: "1", data: "value"}]

    {events, %Parser{}} = Parser.parse("id: a\0b\ndata: value\n\n")
    assert events == [%{data: "value"}]

    {events, %Parser{}} = Parser.parse("id: \0\ndata: value\n\n")
    assert events == [%{data: "value"}]
  end

  test "multiple data lines are concatenated with newlines" do
    {events, %Parser{}} =
      Parser.parse("data: line 1\ndata: line 2\ndata: line 3\n\n")

    assert events == [%{data: "line 1\nline 2\nline 3"}]
  end

  test "multiple data lines arriving in incomplete chunks are still concatenated with newlines" do
    {[], state} = Parser.parse("event: data_")
    {[], state} = Parser.parse(state, "test\nda")
    {[], state} = Parser.parse(state, "ta")
    {[], state} = Parser.parse(state, ": lin")
    {[], state} = Parser.parse(state, "e 1")
    {[], state} = Parser.parse(state, "\ndata: ")
    {[], state} = Parser.parse(state, "line 2")
    {[], state} = Parser.parse(state, "\ndata: line 3\n")
    {events, %Parser{}} = Parser.parse(state, "\n")

    assert events == [%{event: "data_test", data: "line 1\nline 2\nline 3"}]
  end

  describe "comments" do
    test "allows comments but ignores them" do
      # Standalone comment
      {[], %Parser{}} = Parser.parse(": this is a comment\n\n")

      # Standalone comment followed by event
      {[event], %Parser{}} =
        Parser.parse(": this is a comment\n\nid: 1\nevent:foo\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with leading comment
      {[event], %Parser{}} =
        Parser.parse(": this is a comment\nid: 1\nevent:foo\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with comment inside it
      {[event], %Parser{}} =
        Parser.parse("id: 1\nevent:foo\n: this is a comment\ndata: bar\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event with trailing comment
      {[event], %Parser{}} =
        Parser.parse("id: 1\nevent:foo\ndata: bar\n: this is a comment\n\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # Event followed by a standalone comment
      {[event], %Parser{}} =
        Parser.parse("id: 1\nevent:foo\ndata: bar\n\n: this is a comment\n")

      assert event == %{id: "1", event: "foo", data: "bar"}

      # comment in a comment line is still a comment
      {[], %Parser{}} = Parser.parse(": this is a comment: with a colon\n\n")
    end

    test "allows comments but ignores them when split across chunks" do
      {[], state} = Parser.parse("")
      {[], state} = Parser.parse(state, ": ")
      {[], state} = Parser.parse(state, "comments begin with a colon: '")
      {[], state} = Parser.parse(state, ": this is a comment'\n")
      {[], state} = Parser.parse(state, "\n")
      {[], %Parser{}} = Parser.parse(state, "")
    end
  end
end
