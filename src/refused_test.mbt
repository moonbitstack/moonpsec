// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a space is named rather than quoted" {
  let error = @moonpsec.run(@moonpsec.char(' '), "\t").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected tab; expecting space")
}

///|
test "a control character inside a run is named in angle brackets" {
  let error = @moonpsec.run(@moonpsec.string("a\nb"), "a\rc").unwrap_err()
  assert_eq(error.want, [@moonpsec.Item::Tokens("a\nb")])
  assert_eq(
    error.to_string(),
    "1:2: unexpected carriage return; expecting \"a<newline>b\"",
  )
}

///|
test "a carriage return and a line feed have a name of their own" {
  let error = @moonpsec.run(@moonpsec.string("\r\n"), "\r\r").unwrap_err()
  assert_eq(
    error.to_string(),
    "1:2: unexpected carriage return; expecting crlf newline",
  )
}

///|
test "a label is shown as it was written" {
  let error = @moonpsec.run(@moonpsec.digit.label("even digit"), "x").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected 'x'; expecting even digit")
}

///|
test "expectations are sorted and repeated ones appear once" {
  let parser = @moonpsec.char('b')
    .or(@moonpsec.char('a'))
    .or(@moonpsec.char('b'))
  let error = @moonpsec.run(parser, "z").unwrap_err()
  assert_eq(error.want.length(), 2)
  assert_eq(error.to_string(), "1:1: unexpected 'z'; expecting 'a' or 'b'")
}

///|
test "three expectations are joined the way English joins them" {
  let parser = @moonpsec.choice([
    @moonpsec.char('a'),
    @moonpsec.char('b'),
    @moonpsec.char('c'),
  ])
  let error = @moonpsec.run(parser, "z").unwrap_err()
  assert_eq(
    error.to_string(),
    "1:1: unexpected 'z'; expecting 'a', 'b', or 'c'",
  )
}

///|
test "merging two refusals at the same place keeps both expectations" {
  let left = @moonpsec.run(@moonpsec.char('a'), "z").unwrap_err()
  let right = @moonpsec.run(@moonpsec.string("bc"), "z").unwrap_err()
  let merged = left.merge(right)
  assert_eq(merged.position.at, 0)
  assert_eq(merged.want, [
    @moonpsec.Item::Token('a'),
    @moonpsec.Item::Tokens("bc"),
  ])
}

///|
test "merging keeps the refusal that got further" {
  let near = @moonpsec.run(@moonpsec.char('a'), "yz").unwrap_err()
  let far = @moonpsec.run(@moonpsec.take(1).then(@moonpsec.char('a')), "yz").unwrap_err()
  let merged = near.merge(far)
  assert_eq(merged.position.at, 1)
  assert_eq(merged.want, [@moonpsec.Item::Token('a')])
}

///|
test "merging keeps a note from both sides" {
  let silence : @moonpsec.Parser[Unit] = @moonpsec.fail("first")
  let left = @moonpsec.run(silence, "").unwrap_err()
  let other : @moonpsec.Parser[Unit] = @moonpsec.fail("second")
  let right = @moonpsec.run(other, "").unwrap_err()
  let merged = left.merge(right)
  assert_eq(merged.notes, ["first", "second"])
}

///|
test "a refusal with nothing to say says so" {
  let error : @moonpsec.Refused = {
    position: @moonpsec.start,
    got: None,
    want: [],
    notes: [],
  }
  assert_eq(error.message(), "unknown parse error")
  assert_eq(error.to_string(), "1:1: unknown parse error")
}

///|
test "the message is the two lines a compiler prints" {
  let error = @moonpsec.run(@moonpsec.char('b'), "a").unwrap_err()
  assert_eq(error.message(), "unexpected 'a'\nexpecting 'b'")
}

///|
test "a note is printed under the expectations" {
  let out_of_range : @moonpsec.Parser[Unit] = @moonpsec.fail(
    "the number is out of range",
  )
  let error = @moonpsec.run(out_of_range, "").unwrap_err()
  assert_eq(error.message(), "the number is out of range")
}

///|
test "a rendered refusal points at the character with a caret" {
  let error = @moonpsec.run(@moonpsec.char('b'), "abc").unwrap_err()
  assert_eq(
    error.pretty("abc"),
    "1:1:\n  |\n1 | abc\n  | ^\nunexpected 'a'\nexpecting 'b'",
  )
}

///|
test "a rendered refusal shows the line it happened on" {
  let parser = @moonpsec.take_while(ch => ch != '\n')
    .skip(@moonpsec.newline)
    .then(@moonpsec.char('x'))
  let error = @moonpsec.run(parser, "one\ntwo").unwrap_err()
  assert_eq(
    error.pretty("one\ntwo"),
    "2:1:\n  |\n2 | two\n  | ^\nunexpected 't'\nexpecting 'x'",
  )
}

///|
test "a rendered refusal expands a tab so the caret lines up" {
  let error = @moonpsec.run(@moonpsec.take(1).then(@moonpsec.char('x')), "\ty").unwrap_err()
  assert_eq(
    error.pretty("\ty"),
    "1:9:\n  |\n1 |         y\n  |         ^\nunexpected 'y'\nexpecting 'x'",
  )
}

///|
test "a rendered refusal counts a wide character as two columns" {
  let error = @moonpsec.run(@moonpsec.take(1).then(@moonpsec.char('x')), "日y").unwrap_err()
  assert_eq(
    error.pretty("日y"),
    "1:2:\n  |\n1 | 日y\n  |   ^\nunexpected 'y'\nexpecting 'x'",
  )
}

///|
test "a refusal at the end of a line points past its last character" {
  let error = @moonpsec.run(@moonpsec.take_rest.then(@moonpsec.char('x')), "ab").unwrap_err()
  assert_eq(
    error.pretty("ab"),
    "1:3:\n  |\n1 | ab\n  |   ^\nunexpected end of input\nexpecting 'x'",
  )
}

///|
test "the compact form of a refusal is one line" {
  let error = @moonpsec.run(@moonpsec.char('b'), "a").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected 'a'; expecting 'b'")
  assert_eq(error.to_string().contains("\n"), false)
}
