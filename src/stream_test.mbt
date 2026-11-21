// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a feeder asks for more until the text ends" {
  let feeder = @moonpsec.feeder(@moonpsec.string("abc").eof())
  assert_eq(feeder.feed("a") is @moonpsec.Progress::Needs(_), true)
  assert_eq(feeder.feed("b") is @moonpsec.Progress::Needs(_), true)
  assert_eq(feeder.feed("c") is @moonpsec.Progress::Needs(_), true)
  assert_eq(feeder.finish().unwrap(), "abc")
}

///|
test "a feeder reports a refusal as soon as it is sure" {
  let feeder = @moonpsec.feeder(@moonpsec.string("abc").eof())
  let answer = feeder.feed("ax")
  assert_eq(answer is @moonpsec.Progress::Failed(_), true)
  match answer {
    Failed(error) => {
      assert_eq(error.position.at, 1)
      assert_eq(error.got, Some(@moonpsec.Item::Token('x')))
    }
    _ => abort("expected a refusal")
  }
}

///|
test "a feeder does not refuse what might still arrive" {
  let feeder = @moonpsec.feeder(@moonpsec.char('a').eof())
  assert_eq(feeder.feed("") is @moonpsec.Progress::Needs(_), true)
  assert_eq(feeder.feed("a") is @moonpsec.Progress::Needs(_), true)
  let answer = feeder.feed("b")
  assert_eq(answer.refusal().unwrap().position.at, 1)
}

///|
test "a grammar for a prefix is answered before the text ends" {
  let feeder = @moonpsec.feeder(
    @moonpsec.take_while1(ch => ch.is_ascii_digit()),
  )
  match feeder.feed("12ab") {
    Ready(value, rest) => {
      assert_eq(value, "12")
      assert_eq(rest.to_owned(), "ab")
    }
    _ => abort("expected a value")
  }
}

///|
test "a grammar for a prefix waits when the prefix might continue" {
  let feeder = @moonpsec.feeder(
    @moonpsec.take_while1(ch => ch.is_ascii_digit()),
  )
  assert_eq(feeder.feed("12") is @moonpsec.Progress::Needs(_), true)
  assert_eq(feeder.feed("3x").is_ready(), true)
}

///|
test "a scan does not stop at the boundary of a chunk" {
  let parser = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic()).eof()
  assert_eq(
    @moonpsec.stream(parser, ["ab"[:], "cd"[:]].iter()).unwrap(),
    "abcd",
  )
}

///|
test "a string split across chunks is read as one" {
  let parser = @moonpsec.string("hello").eof()
  assert_eq(
    @moonpsec.stream(parser, ["he"[:], "ll"[:], "o"[:]].iter()).unwrap(),
    "hello",
  )
}

///|
test "a refusal in a later chunk points into the text fed so far" {
  let parser = @moonpsec.take_while1(ch => ch.is_ascii_digit())
    .skip(@moonpsec.char(';'))
    .eof()
  let error = @moonpsec.stream(parser, ["12"[:], "3,"[:]].iter()).unwrap_err()
  assert_eq(error.position.at, 3)
  assert_eq(error.position.column, 4)
}

///|
test "finishing refuses text that the grammar did not describe" {
  let feeder = @moonpsec.feeder(@moonpsec.string("ab"))
  let _ = feeder.feed("abc")
  let error = feeder.finish().unwrap_err()
  assert_eq(error.position.at, 2)
  assert_eq(error.want, [@moonpsec.Item::End])
}

///|
test "finishing a text the grammar needed more of names the end" {
  let feeder = @moonpsec.feeder(@moonpsec.string("abc"))
  let _ = feeder.feed("a")
  let error = feeder.finish().unwrap_err()
  assert_eq(error.position.at, 1)
  assert_eq(error.got, Some(@moonpsec.Item::End))
}

///|
test "a feeder keeps the text it was given" {
  let feeder = @moonpsec.feeder(@moonpsec.eof)
  let _ = feeder.feed("ab")
  let _ = feeder.feed("cd")
  assert_eq(feeder.text().to_owned(), "abcd")
}

///|
test "a refusal can be rendered against the text fed so far" {
  let feeder = @moonpsec.feeder(
    @moonpsec.take_while1(ch => ch.is_ascii_digit()).eof(),
  )
  let _ = feeder.feed("ab")
  match feeder.finish() {
    Err(error) => assert_eq(error.pretty(feeder.text()).contains("ab"), true)
    Ok(_) => abort("expected a refusal")
  }
}

///|
test "streaming a document one chunk at a time reads the same as reading it whole" {
  let parser = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic())
    .skip(@moonpsec.char(':'))
    .then(@moonpsec.take_while1(ch => ch.is_ascii_digit()))
    .eof()
  let whole = @moonpsec.run(parser, "key:42").unwrap()
  let pieces = @moonpsec.stream(
    parser,
    ["k"[:], "ey:"[:], "4"[:], "2"[:]].iter(),
  ).unwrap()
  assert_eq(pieces, whole)
}
