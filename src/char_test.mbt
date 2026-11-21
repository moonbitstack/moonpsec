// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "char reads the character it was given" {
  assert_eq(@moonpsec.run(@moonpsec.char('a'), "a"), Ok('a'))
  assert_eq(
    @moonpsec.run(@moonpsec.char('a'), "b"),
    Err({
      position: { at: 0, line: 1, column: 1, },
      got: Some(@moonpsec.Item::Token('b')),
      want: [@moonpsec.Item::Token('a')],
      notes: [],
    }),
  )
}

///|
test "char at the end of the text names the end" {
  let error = @moonpsec.run(@moonpsec.char('a'), "").unwrap_err()
  assert_eq(error.got, Some(@moonpsec.Item::End))
  assert_eq(error.to_string(), "1:1: unexpected end of input; expecting 'a'")
}

///|
test "char reads a character above the basic plane as one character" {
  assert_eq(
    @moonpsec.run(@moonpsec.char('\u{20000}'), "\u{20000}"),
    Ok('\u{20000}'),
  )
}

///|
test "char_ci accepts either case and produces what the text has" {
  assert_eq(@moonpsec.run(@moonpsec.char_ci('a'), "A"), Ok('A'))
  assert_eq(@moonpsec.run(@moonpsec.char_ci('A'), "a"), Ok('a'))
}

///|
test "char_ci leaves characters without a case alone" {
  assert_eq(@moonpsec.run(@moonpsec.char_ci('1'), "1"), Ok('1'))
  let error = @moonpsec.run(@moonpsec.char_ci('1'), "2").unwrap_err()
  assert_eq(error.want, [@moonpsec.Item::Token('1')])
}

///|
test "one_of reads any of the characters it was given" {
  let vowel = @moonpsec.one_of("aeiou")
  assert_eq(@moonpsec.run(vowel, "e"), Ok('e'))
  assert_eq(
    @moonpsec.run(vowel, "x"),
    Err({
      position: { at: 0, line: 1, column: 1, },
      got: Some(@moonpsec.Item::Token('x')),
      want: [@moonpsec.Item::Tokens("aeiou")],
      notes: [],
    }),
  )
}

///|
test "none_of reads anything but the characters it was given" {
  let consonant = @moonpsec.none_of("aeiou")
  assert_eq(@moonpsec.run(consonant, "x"), Ok('x'))
  let error = @moonpsec.run(consonant, "a").unwrap_err()
  assert_eq(error.got, Some(@moonpsec.Item::Token('a')))
  assert_eq(error.want, [])
}

///|
test "digit takes the ten ASCII digits and nothing else" {
  for ch in "0123456789" {
    assert_eq(@moonpsec.run(@moonpsec.digit, ch.to_string()), Ok(ch))
  }
  assert_true(refused(@moonpsec.run(@moonpsec.digit, "x")))
}

///|
test "digit refuses a digit of another script" {
  let error = @moonpsec.run(@moonpsec.digit, "٣").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected '٣'; expecting digit")
}

///|
test "hex_digit takes both cases" {
  for ch in "0123456789abcdefABCDEF" {
    assert_eq(@moonpsec.run(@moonpsec.hex_digit, ch.to_string()), Ok(ch))
  }
  assert_true(refused(@moonpsec.run(@moonpsec.hex_digit, "g")))
}

///|
test "oct_digit stops at seven" {
  assert_eq(@moonpsec.run(@moonpsec.oct_digit, "7"), Ok('7'))
  assert_true(refused(@moonpsec.run(@moonpsec.oct_digit, "8")))
}

///|
test "letter is an ASCII letter" {
  assert_eq(@moonpsec.run(@moonpsec.letter, "Q"), Ok('Q'))
  assert_true(refused(@moonpsec.run(@moonpsec.letter, "7")))
}

///|
test "alpha_num takes a letter or a digit" {
  assert_eq(@moonpsec.run(@moonpsec.alpha_num, "a"), Ok('a'))
  assert_eq(@moonpsec.run(@moonpsec.alpha_num, "9"), Ok('9'))
  assert_true(refused(@moonpsec.run(@moonpsec.alpha_num, "_")))
}

///|
test "space takes one whitespace character of any script" {
  assert_eq(@moonpsec.run(@moonpsec.space, " "), Ok(' '))
  assert_eq(@moonpsec.run(@moonpsec.space, "\t"), Ok('\t'))
  assert_eq(@moonpsec.run(@moonpsec.space, "\u{3000}"), Ok('\u{3000}'))
  assert_true(refused(@moonpsec.run(@moonpsec.space, "x")))
}

///|
test "space1 reads a run of whitespace and refuses an empty one" {
  let (_, rest) = @moonpsec.run_partial(@moonpsec.space1, "   x").unwrap()
  assert_eq(rest.to_owned(), "x")
  let error = @moonpsec.run(@moonpsec.space1, "x").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected 'x'; expecting white space")
}

///|
test "newline takes a line feed and nothing else" {
  assert_eq(@moonpsec.run(@moonpsec.newline, "\n"), Ok('\n'))
  assert_true(refused(@moonpsec.run(@moonpsec.newline, "\r")))
}

///|
test "crlf takes a carriage return and a line feed" {
  assert_eq(@moonpsec.run(@moonpsec.crlf, "\r\n"), Ok(()))
  let error = @moonpsec.run(@moonpsec.crlf, "\rx").unwrap_err()
  assert_eq(error.to_string(), "1:2: unexpected 'x'; expecting crlf newline")
}

///|
test "tab takes a horizontal tab" {
  assert_eq(@moonpsec.run(@moonpsec.tab, "\t"), Ok('\t'))
  assert_true(refused(@moonpsec.run(@moonpsec.tab, " ")))
}

///|
test "upper and lower take one case each" {
  assert_eq(@moonpsec.run(@moonpsec.upper, "A"), Ok('A'))
  assert_true(refused(@moonpsec.run(@moonpsec.upper, "a")))
  assert_eq(@moonpsec.run(@moonpsec.lower, "a"), Ok('a'))
  assert_true(refused(@moonpsec.run(@moonpsec.lower, "A")))
}

///|
test "control takes a control character" {
  assert_eq(@moonpsec.run(@moonpsec.control, "\u{7}"), Ok('\u{7}'))
  assert_true(refused(@moonpsec.run(@moonpsec.control, "a")))
}

///|
test "printable takes a character a terminal draws" {
  assert_eq(@moonpsec.run(@moonpsec.printable, "a"), Ok('a'))
  assert_true(refused(@moonpsec.run(@moonpsec.printable, "\u{7}")))
}

///|
test "ascii refuses anything above the basic range" {
  assert_eq(@moonpsec.run(@moonpsec.ascii, "~"), Ok('~'))
  assert_true(refused(@moonpsec.run(@moonpsec.ascii, "é")))
}

///|
test "punctuation takes an ASCII punctuation mark" {
  assert_eq(@moonpsec.run(@moonpsec.punctuation, "?"), Ok('?'))
  assert_true(refused(@moonpsec.run(@moonpsec.punctuation, "a")))
}

///|
test "blank takes a space or a tab but not a newline" {
  assert_eq(@moonpsec.run(@moonpsec.blank, " "), Ok(' '))
  assert_true(refused(@moonpsec.run(@moonpsec.blank, "\n")))
}

///|
test "satisfy without a name says only what it found" {
  let error = @moonpsec.run(@moonpsec.satisfy(ch => ch == 'x'), "y").unwrap_err()
  assert_eq(error.to_string(), "1:1: unexpected 'y'")
  assert_eq(error.want, [])
}

///|
test "satisfy with a name says what it wanted" {
  let even = @moonpsec.satisfy(
    ch => ch == '8',
    want=@moonpsec.Item::Tokens("02468"),
  )
  let error = @moonpsec.run(even, "3").unwrap_err()
  assert_eq(error.want, [@moonpsec.Item::Tokens("02468")])
}

///|
test "any_char takes one character and names the end of the text" {
  assert_eq(@moonpsec.run(@moonpsec.any_char, "z"), Ok('z'))
  let error = @moonpsec.run(@moonpsec.any_char, "").unwrap_err()
  assert_eq(error.got, Some(@moonpsec.Item::End))
  assert_eq(error.want, [])
}
