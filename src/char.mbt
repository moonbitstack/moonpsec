// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads exactly `ch`.
///
/// ```mbt check
/// test {
///   assert_eq(@moonpsec.run(@moonpsec.char('a'), "a"), Ok('a'))
/// }
/// ```
pub fn char(ch : Char) -> Parser[Char] {
  satisfy(each => each == ch, want=Item::Token(ch))
}

///|
/// Reads `ch` in either case, which is how a grammar accepts `NULL` and `null`
/// without listing both.
///
/// The comparison folds the two ASCII cases only; letters outside ASCII have
/// case pairs that need a Unicode table, so they have to be listed.
pub fn char_ci(ch : Char) -> Parser[Char] {
  let lower = ch.to_ascii_lowercase()
  satisfy(each => each.to_ascii_lowercase() == lower, want=Item::Token(ch))
}

///|
/// Reads one character out of `set`.
pub fn one_of(set : StringView) -> Parser[Char] {
  satisfy(each => set_has(set, each), want=Item::Tokens(set.to_owned()))
}

///|
/// Reads one character that is not in `set`.
pub fn none_of(set : StringView) -> Parser[Char] {
  satisfy(each => !set_has(set, each))
}

///|
fn set_has(set : StringView, ch : Char) -> Bool {
  for each in set {
    if each == ch {
      return true
    }
  }
  false
}

///|
/// Reads a decimal digit. Only the ten ASCII digits count: every number
/// notation a grammar is likely to describe spells its digits this way, and a
/// script's own digits are a different question from what the number means.
pub let digit : Parser[Char] = satisfy(ch => ch.is_ascii_digit()).label("digit")

///|
/// Reads a hexadecimal digit, either case.
pub let hex_digit : Parser[Char] = satisfy(ch => ch.is_ascii_hexdigit()).label(
  "hexadecimal digit",
)

///|
/// Reads an octal digit.
pub let oct_digit : Parser[Char] = satisfy(ch => ch >= '0' && ch <= '7').label(
  "octal digit",
)

///|
/// Reads an ASCII letter.
pub let letter : Parser[Char] = satisfy(ch => ch.is_ascii_alphabetic()).label(
  "letter",
)

///|
/// Reads an ASCII letter or a decimal digit.
pub let alpha_num : Parser[Char] = satisfy(ch => {
  ch.is_ascii_alphabetic() || ch.is_ascii_digit()
}).label("alphanumeric character")

///|
/// Reads one whitespace character, of any script's spaces.
pub let space : Parser[Char] = satisfy(ch => ch.is_whitespace()).label(
  "white space",
)

///|
/// Reads whitespace until it runs out, and reads nothing if there is none.
pub let space1 : Parser[Unit] = space.skip_many1().label("white space")

///|
/// Reads a line feed.
pub let newline : Parser[Char] = satisfy(ch => ch == '\n').label("newline")

///|
/// Reads a carriage return followed by a line feed, the line ending of HTTP
/// and of every text file that came through Windows.
pub let crlf : Parser[Unit] = char('\r')
  .then(char('\n'))
  .map(_ => ())
  .label("crlf newline")

///|
/// Reads a horizontal tab.
pub let tab : Parser[Char] = satisfy(ch => ch == '\t').label("tab")

///|
/// Reads an uppercase ASCII letter.
pub let upper : Parser[Char] = satisfy(ch => ch.is_ascii_uppercase()).label(
  "uppercase letter",
)

///|
/// Reads a lowercase ASCII letter.
pub let lower : Parser[Char] = satisfy(ch => ch.is_ascii_lowercase()).label(
  "lowercase letter",
)

///|
/// Reads a control character.
pub let control : Parser[Char] = satisfy(ch => ch.is_control()).label(
  "control character",
)

///|
/// Reads a character that a terminal draws, which is what a lexer wants when
/// the text may be pasted from anywhere.
pub let printable : Parser[Char] = satisfy(ch => ch.is_printable()).label(
  "printable character",
)

///|
/// Reads an ASCII character, refusing anything above U+007F.
pub let ascii : Parser[Char] = satisfy(ch => ch.is_ascii()).label(
  "ASCII character",
)

///|
/// Reads an ASCII punctuation character.
pub let punctuation : Parser[Char] = satisfy(ch => ch.is_ascii_punctuation()).label(
  "punctuation",
)

///|
/// Reads an ASCII space or tab, the two characters that separate tokens
/// without ending a line.
pub let blank : Parser[Char] = satisfy(ch => ch == ' ' || ch == '\t').label(
  "blank",
)
