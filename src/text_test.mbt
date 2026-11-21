// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "string reads exactly what it was given" {
  assert_eq(@moonpsec.run(@moonpsec.string("let"), "let"), Ok("let"))
  let (value, rest) = @moonpsec.run_partial(@moonpsec.string("let"), "letter").unwrap()
  assert_eq(value, "let")
  assert_eq(rest.to_owned(), "ter")
}

///|
test "string names the whole run when the first character is wrong" {
  let error = @moonpsec.run(@moonpsec.string("let"), "x").unwrap_err()
  assert_eq(error.position.at, 0)
  assert_eq(error.got, Some(@moonpsec.Item::Token('x')))
  assert_eq(error.want, [@moonpsec.Item::Tokens("let")])
}

///|
test "string points at the character that broke the run" {
  let error = @moonpsec.run(@moonpsec.string("let"), "lex").unwrap_err()
  assert_eq(error.position.at, 2)
  assert_eq(error.to_string(), "1:3: unexpected 'x'; expecting \"let\"")
}

///|
test "string at the end of the text names the end" {
  let error = @moonpsec.run(@moonpsec.string("let"), "le").unwrap_err()
  assert_eq(error.position.at, 2)
  assert_eq(error.got, Some(@moonpsec.Item::End))
  assert_eq(error.want, [@moonpsec.Item::Tokens("let")])
}

///|
test "string of nothing reads nothing" {
  let (value, rest) = @moonpsec.run_partial(@moonpsec.string(""), "abc").unwrap()
  assert_eq(value, "")
  assert_eq(rest.to_owned(), "abc")
}

///|
test "string_ci reads either case and keeps what the text had" {
  assert_eq(@moonpsec.run(@moonpsec.string_ci("null"), "NULL"), Ok("NULL"))
  assert_eq(@moonpsec.run(@moonpsec.string_ci("NULL"), "null"), Ok("null"))
  assert_true(refused(@moonpsec.run(@moonpsec.string_ci("null"), "nul")))
}

///|
test "take_while reads a prefix and stops at the first refusal" {
  let digits = @moonpsec.take_while(ch => ch.is_ascii_digit())
  let (value, rest) = @moonpsec.run_partial(digits, "123abc").unwrap()
  assert_eq(value, "123")
  assert_eq(rest.to_owned(), "abc")
}

///|
test "take_while reads nothing when the first character is not wanted" {
  let (value, rest) = @moonpsec.run_partial(
    @moonpsec.take_while(_ => false),
    "abc",
  ).unwrap()
  assert_eq(value, "")
  assert_eq(rest.to_owned(), "abc")
}

///|
test "take_while1 refuses when there is nothing to take" {
  let word = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic())
  let error = @moonpsec.run(word, "1").unwrap_err()
  assert_eq(error.got, Some(@moonpsec.Item::Token('1')))
  assert_eq(@moonpsec.run(word, "abc"), Ok("abc"))
}

///|
test "take_while1 at the end of the text names the end" {
  let error = @moonpsec.run(@moonpsec.take_while1(_ => true), "").unwrap_err()
  assert_eq(error.got, Some(@moonpsec.Item::End))
}

///|
test "take_rest reads to the end of the text" {
  let (value, place) = @moonpsec.parse(
    @moonpsec.any_char.then(@moonpsec.take_rest),
    "abc",
  ).unwrap()
  assert_eq(value, "bc")
  assert_eq(place.column, 4)
}

///|
test "take_rest moves the position over what it reads" {
  let parser = @moonpsec.take_rest.then(@moonpsec.position)
  let (place, _) = @moonpsec.run_position(parser, "a\nbc").unwrap()
  assert_eq(place.line, 2)
  assert_eq(place.column, 3)
}

///|
test "take reads the number of characters it was given" {
  assert_eq(@moonpsec.run(@moonpsec.take(3), "abc"), Ok("abc"))
  let error = @moonpsec.run(@moonpsec.take(3), "ab").unwrap_err()
  assert_eq(error.position.at, 2)
  assert_eq(error.got, Some(@moonpsec.Item::End))
}

///|
test "take counts characters, not code units" {
  let (value, _) = @moonpsec.run_position(@moonpsec.take(2), "a\u{20000}b").unwrap()
  assert_eq(value, "a\u{20000}")
}

///|
test "eof succeeds only at the end" {
  assert_eq(@moonpsec.run(@moonpsec.eof, ""), Ok(()))
  let error = @moonpsec.run(@moonpsec.eof, "a").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected 'a'; expecting end of input")
}

///|
test "at_end answers without insisting" {
  let parser = @moonpsec.at_end.then(@moonpsec.take_rest)
  assert_eq(@moonpsec.run(parser, "").unwrap(), "")
  assert_eq(@moonpsec.run_partial(@moonpsec.at_end, "a").unwrap().0, false)
}

///|
test "a parser that ends with eof refuses text after the value" {
  let word = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic()).eof()
  let error = @moonpsec.run(word, "ab1").unwrap_err()
  assert_eq(error.position.at, 2)
  assert_eq(error.want, [@moonpsec.Item::End])
}

///|
test "text inside the basic plane is counted one column each" {
  let (_, place) = @moonpsec.parse(@moonpsec.take(3), "日本語").unwrap()
  assert_eq(place.at, 3)
  assert_eq(place.column, 4)
}

///|
test "a character above the basic plane takes two code units and one column" {
  let (_, place) = @moonpsec.parse(@moonpsec.take(2), "😀!").unwrap()
  assert_eq(place.at, 3)
  assert_eq(place.column, 3)
}

///|
test "the offset of a refusal is a code unit offset" {
  let parser = @moonpsec.take(2).then(@moonpsec.char('x'))
  let error = @moonpsec.run(parser, "😀y").unwrap_err()
  assert_eq(error.position.at, 3)
  assert_eq(error.position.column, 3)
}
