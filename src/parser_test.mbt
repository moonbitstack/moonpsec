// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "map changes the value and leaves the position alone" {
  let word = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic())
  let (length, end) = @moonpsec.parse(word.map(text => text.length()), "hello").unwrap()
  assert_eq(length, 5)
  assert_eq(end.column, 6)
}

///|
test "and_then decides what follows from what came before" {
  let counted = @moonpsec.digit.and_then(first => {
    let count = first.to_int() - '0'.to_int()
    @moonpsec.take_while(ch => ch == '.').count(count)
  })
  assert_eq(@moonpsec.run(counted, "3...").unwrap().length(), 3)
}

///|
test "then keeps the right value and skip keeps the left" {
  let quoted = @moonpsec.char('"')
    .then(@moonpsec.take_while(ch => ch != '"'))
    .skip(@moonpsec.char('"'))
  assert_eq(@moonpsec.run(quoted, "\"hi\""), Ok("hi"))
}

///|
test "or reports both alternatives when neither matches" {
  let letter = @moonpsec.char('a').or(@moonpsec.char('b'))
  let error = @moonpsec.run(letter, "c").unwrap_err()
  assert_eq(error.position.at, 0)
  assert_eq(error.got, Some(@moonpsec.Item::Token('c')))
  assert_eq(error.want, [@moonpsec.Item::Token('a'), @moonpsec.Item::Token('b')])
  assert_eq(error.to_string(), "1:1: unexpected 'c'; expecting 'a' or 'b'")
}

///|
test "a branch that read something is not undone by or" {
  let parser = @moonpsec.string("ab").or(@moonpsec.string("ac"))
  let error = @moonpsec.run(parser, "ac").unwrap_err()
  assert_eq(error.position.at, 1)
  assert_eq(error.got, Some(@moonpsec.Item::Token('c')))
  assert_eq(error.want, [@moonpsec.Item::Tokens("ab")])
}

///|
test "attempt lets the other branch be tried" {
  let parser = @moonpsec.string("ab").attempt().or(@moonpsec.string("ac"))
  assert_eq(@moonpsec.run(parser, "ac"), Ok("ac"))
}

///|
test "attempt keeps the refusal at the place it happened" {
  let parser = @moonpsec.string("ab").attempt()
  let error = @moonpsec.run(parser, "ax").unwrap_err()
  assert_eq(error.position.at, 1)
  assert_eq(error.got, Some(@moonpsec.Item::Token('x')))
}

///|
test "the farther of two refusals is the one reported" {
  let parser = @moonpsec.string("abc")
    .attempt()
    .or(@moonpsec.string("abx").attempt())
  let error = @moonpsec.run(parser, "abz").unwrap_err()
  assert_eq(error.position.at, 2)
  assert_eq(
    error.to_string(),
    "1:3: unexpected 'z'; expecting \"abc\" or \"abx\"",
  )
}

///|
test "many collects what it can and stops at the first refusal" {
  let digits = @moonpsec.digit.many()
  assert_true(refused(@moonpsec.run(digits, "12a")))
  let (values, rest) = @moonpsec.run_partial(digits, "12a").unwrap()
  assert_eq(values.length(), 2)
  assert_eq(rest.to_owned(), "a")
}

///|
test "many of a parser that reads nothing stops instead of spinning" {
  let empty = @moonpsec.pure(1).many()
  assert_eq(@moonpsec.run(empty, "").unwrap().length(), 0)
}

///|
test "many fails when a round reads something and then refuses" {
  let parser = @moonpsec.string("ab").many()
  let error = @moonpsec.run_partial(parser, "abax").unwrap_err()
  assert_eq(error.position.at, 3)
}

///|
test "many1 requires one match" {
  let digits = @moonpsec.digit.many1()
  assert_eq(@moonpsec.run_partial(digits, "7x").unwrap().0.length(), 1)
  let error = @moonpsec.run(digits, "x").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected 'x'; expecting digit")
}

///|
test "sep_by reads nothing for empty text" {
  let numbers = @moonpsec.digit.many1().sep_by(@moonpsec.char(','))
  assert_eq(@moonpsec.run(numbers, "").unwrap().length(), 0)
  let values = @moonpsec.run(numbers, "1,23,4").unwrap()
  assert_eq(values.length(), 3)
  assert_eq(values[1].length(), 2)
}

///|
test "sep_by reads a separator only as part of a value" {
  let numbers = @moonpsec.digit.many1().sep_by(@moonpsec.char(','))
  assert_eq(@moonpsec.run(numbers, "1,2").unwrap().length(), 2)
  // A separator that nothing follows is a refusal, not a stop: the list was
  // committed to another element the moment the comma was read.
  assert_true(refused(@moonpsec.run(numbers, "1,2,")))
}

///|
test "sep_end_by reads the separator after the last value" {
  let numbers = @moonpsec.digit.many1().sep_end_by(@moonpsec.char(';'))
  let (values, rest) = @moonpsec.run_partial(numbers, "1;2;").unwrap()
  assert_eq(values.length(), 2)
  assert_eq(rest.to_owned(), "")
}

///|
test "between reads the brackets and keeps the inside" {
  let inside = @moonpsec.between(
    @moonpsec.char('('),
    @moonpsec.char(')'),
    @moonpsec.digit.many1(),
  )
  assert_eq(@moonpsec.run(inside, "(42)").unwrap().length(), 2)
}

///|
test "optional produces nothing when the parser does not match" {
  let sign = @moonpsec.char('-').optional()
  assert_eq(@moonpsec.run(sign, "-"), Ok(Some('-')))
  assert_eq(@moonpsec.run(sign, ""), Ok(None))
}

///|
test "optional does not swallow a refusal that read something" {
  let parser = @moonpsec.string("ab").optional()
  assert_true(refused(@moonpsec.run_partial(parser, "ax")))
}

///|
test "count runs exactly the given number of times" {
  let three = @moonpsec.any_char.count(3)
  assert_eq(@moonpsec.run(three, "abc").unwrap().length(), 3)
  assert_true(refused(@moonpsec.run(three, "ab")))
}

///|
test "choice tries the alternatives in order" {
  let keyword = @moonpsec.choice([
    @moonpsec.string("let"),
    @moonpsec.string("letrec"),
    @moonpsec.take_while1(ch => ch.is_ascii_alphabetic()),
  ])
  assert_eq(@moonpsec.run(keyword, "let"), Ok("let"))
  assert_true(refused(@moonpsec.run(keyword, "letrec")))
  assert_eq(@moonpsec.run(keyword, "abc"), Ok("abc"))
}

///|
test "choice of nothing refuses with nothing to say" {
  let nothing : @moonpsec.Parser[Unit] = @moonpsec.choice([])
  let error = @moonpsec.run(nothing, "").unwrap_err()
  assert_eq(error.to_string(), "1:1: unknown parse error")
}

///|
test "look_ahead reads without moving" {
  let peek = @moonpsec.string("ab").look_ahead()
  let parser = peek.then(@moonpsec.any_char.count(2))
  assert_eq(@moonpsec.run(parser, "ab").unwrap().length(), 2)
}

///|
test "look_ahead restores the position after a match" {
  let (_, rest) = @moonpsec.run_partial(@moonpsec.any_char.look_ahead(), "abc").unwrap()
  assert_eq(rest.to_owned(), "abc")
}

///|
test "not_followed_by fails on what it must not see" {
  let keyword = @moonpsec.string("if").skip(
    @moonpsec.alpha_num.not_followed_by(),
  )
  let error = @moonpsec.run(keyword, "iffy").unwrap_err()
  assert_eq(error.got, Some(@moonpsec.Item::Token('f')))
  assert_eq(error.want, [])
  assert_eq(@moonpsec.run_partial(keyword, "if(").unwrap().0, "if")
}

///|
test "label replaces everything the parser expected" {
  let integer = @moonpsec.digit.many1().label("integer")
  let error = @moonpsec.run(integer, "x").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected 'x'; expecting integer")
}

///|
test "label keeps what was found" {
  let integer = @moonpsec.digit.many1().label("integer")
  let error = @moonpsec.run(integer, "").unwrap_err()
  assert_eq(error.got, Some(@moonpsec.Item::End))
  assert_eq(
    error.to_string(),
    "1:1: unexpected end of input; expecting integer",
  )
}

///|
test "hidden empties the expectations" {
  let quiet = @moonpsec.digit.many1().hidden()
  let error = @moonpsec.run(quiet, "x").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected 'x'")
}

///|
test "fail refuses without reading" {
  let parser : @moonpsec.Parser[Unit] = @moonpsec.digit.and_then(_ => {
    @moonpsec.fail("odd numbers are not allowed")
  })
  let error = @moonpsec.run(parser, "3").unwrap_err()
  assert_eq(error.position.at, 1)
  assert_eq(error.to_string(), "1:2: odd numbers are not allowed")
}

///|
test "fail does not consume, so a choice can move on" {
  let parser = @moonpsec.pure(())
    .and_then(_ => @moonpsec.fail("no"))
    .or(@moonpsec.pure(2))
  assert_eq(@moonpsec.run(parser, ""), Ok(2))
}

///|
test "position is reported where the parser stands" {
  let parser = @moonpsec.string("ab\ncd").then(@moonpsec.position)
  let (place, _) = @moonpsec.parse(parser, "ab\ncd").unwrap()
  assert_eq(place.at, 5)
  assert_eq(place.line, 2)
  assert_eq(place.column, 3)
}

///|
test "columns count characters, not code units" {
  let parser = @moonpsec.take_while1(_ => true)
  let (_, end) = @moonpsec.parse(parser, "a𠀀b").unwrap()
  assert_eq(end.at, 4)
  assert_eq(end.column, 4)
}

///|
test "a tab counts to the next tab stop" {
  let parser = @moonpsec.take(1).then(@moonpsec.position)
  let (place, _) = @moonpsec.run_position(parser, "\ta").unwrap()
  assert_eq(place.column, 9)
  assert_eq(place.at, 1)
}

///|
test "the tab width is adjustable" {
  let parser = @moonpsec.take(1).then(@moonpsec.position)
  let (place, _) = @moonpsec.run_position(parser, "\ta", tab=4).unwrap()
  assert_eq(place.column, 5)
}

///|
test "run refuses text that was left over" {
  let error = @moonpsec.run(@moonpsec.char('a'), "ab").unwrap_err()
  assert_eq(error.position.at, 1)
  assert_eq(error.to_string(), "1:2: unexpected 'b'; expecting end of input")
}

///|
test "run_partial says where it stopped" {
  let (value, rest) = @moonpsec.run_partial(@moonpsec.char('a'), "ab").unwrap()
  assert_eq(value, 'a')
  assert_eq(rest.to_owned(), "b")
}

///|
test "run reports a line and column in the text" {
  let parser = @moonpsec.take_while(ch => ch != '\n')
    .skip(@moonpsec.newline)
    .skip(@moonpsec.take_while(ch => ch != '\n'))
    .skip(@moonpsec.newline)
    .then(@moonpsec.char('x'))
  let error = @moonpsec.run(parser, "one\ntwo\nthree").unwrap_err()
  assert_eq(error.position.line, 3)
  assert_eq(error.position.column, 1)
  assert_eq(error.to_string(), "3:1: unexpected 't'; expecting 'x'")
}

///|
test "recover_with keeps the refusal next to the value" {
  let digit = @moonpsec.digit.label("digit")
  let forgiving = digit.recover_with(_ => {
    @moonpsec.pure('0').skip(@moonpsec.any_char)
  })
  let repair = @moonpsec.run(forgiving, "x").unwrap()
  assert_eq(repair.value, '0')
  assert_eq(repair.refusal.unwrap().position.at, 0)
}

///|
test "recover_with resumes where the refusal pointed" {
  let tolerant = @moonpsec.digit.recover_with(_ => {
    @moonpsec.any_char.map(_ => '?')
  })
  let parser = tolerant.many()
  let repairs = @moonpsec.run(parser, "1a2").unwrap()
  assert_eq(repairs.length(), 3)
  assert_eq(repairs[1].value, '?')
  assert_eq(repairs[1].refusal is Some(_), true)
  assert_eq(repairs[2].refusal is None, true)
}

///|
test "a recovered parser still refuses when the recovery refuses" {
  let parser = @moonpsec.digit.recover_with(_ => @moonpsec.char('!'))
  let error = @moonpsec.run(parser, "ab").unwrap_err()
  assert_eq(error.position.at, 0)
  assert_eq(error.want, [@moonpsec.Item::Label("digit")])
}
