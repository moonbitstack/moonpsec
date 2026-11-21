// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How deep a document may nest.
///
/// RFC 8259 leaves the limit to the reader, and a reader without one takes the
/// stack down on a document of a hundred thousand open brackets. A hundred and
/// twenty-eight levels is deeper than any document written for people, and it
/// is what every backend this library runs on can nest without running out of
/// stack: each level costs several frames, and the smallest stack of the four
/// is the one that sets the number.
let max_depth : Int32 = 128

///|
/// Reads one JSON document and refuses anything after it.
///
/// ```mbt check
/// test {
///   let document = @json.parse("[1, \"two\", null]").unwrap()
///   assert_eq(document.to_string(), "[1,\"two\",null]")
/// }
/// ```
pub fn parse(text : StringView) -> Result[Value, @moonpsec.Refused] {
  @moonpsec.run(document, text)
}

///|
/// The whole document: a value with whitespace around it, and then the end.
let document : @moonpsec.Parser[Value] = byte_order_mark
  .then(whitespace)
  .then(value_at(max_depth))
  .skip(whitespace)
  .eof()

///|
/// A byte order mark at the very start, which RFC 8259 §8.1 forbids writing
/// and does not forbid skipping: a document that came from an editor on
/// Windows often has one, and refusing it would be a pedantry about the first
/// character that says nothing about the document.
let byte_order_mark : @moonpsec.Parser[Unit] = @moonpsec.char('\u{FEFF}')
  .map(_ => ())
  .or(@moonpsec.pure(()))

///|
/// Whitespace between tokens, of which RFC 8259 knows four characters.
let whitespace : @moonpsec.Parser[String] = @moonpsec.take_while(ch => {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
})

///|
fn[T] token(parser : @moonpsec.Parser[T]) -> @moonpsec.Parser[T] {
  parser.skip(whitespace)
}

///|
/// The value parser for a document nested `depth` levels deep.
///
/// The limit is applied while the parser is being built rather than while it
/// runs: each level holds a parser for the level inside it, and the innermost
/// one refuses. Nothing is counted at run time, so a grammar can be run twice
/// at once without the two runs seeing each other.
fn value_at(depth : Int32) -> @moonpsec.Parser[Value] {
  if depth == 0 {
    return too_deep()
  }
  let inside = value_at(depth - 1)
  let literal = token(
    @moonpsec.choice([
      @moonpsec.string("null").map(_ => Value::Null),
      @moonpsec.string("true").map(_ => Value::True),
      @moonpsec.string("false").map(_ => Value::False),
    ]),
  )
  let number = token(number_text()).map(text => Value::Number(text))
  let text = token(text_value()).map(text => Value::Text(text))
  let elements = token(inside).sep_by(token(@moonpsec.char(',')))
  let array = @moonpsec.between(
    token(@moonpsec.char('[')),
    token(@moonpsec.char(']')),
    elements,
  ).map(items => Value::Array(items))
  let members = member_of(inside).sep_by(token(@moonpsec.char(',')))
  let object = @moonpsec.between(
    token(@moonpsec.char('{')),
    token(@moonpsec.char('}')),
    members,
  ).map(members => {
    let gathered = []
    for pair in members {
      ignore(with_member(gathered, pair.0, pair.1))
    }
    Value::Object(gathered)
  })
  literal.or(number).or(text).or(array).or(object).label("a JSON value")
}

///|
/// What the parser says when a document nests past the limit.
///
/// The opening bracket is read before the refusal so that the refusal is not
/// something a list may shrug off as "no element here, then" — without that,
/// the limit would be reported as a missing close bracket, which says nothing
/// about why the document was refused.
fn too_deep() -> @moonpsec.Parser[Value] {
  let opening = @moonpsec.char('[').or(@moonpsec.char('{'))
  opening.then(@moonpsec.fail("nesting is deeper than \{max_depth} levels"))
}

///|
fn member_of(
  inside : @moonpsec.Parser[Value],
) -> @moonpsec.Parser[(String, Value)] {
  let name = token(text_value())
  let colon = token(@moonpsec.char(':'))
  name.and_then(each => colon.then(token(inside)).map(value => (each, value)))
}

///|
/// Puts a member into an object, replacing an earlier member of the same name
/// in place rather than keeping both.
///
/// RFC 8259 §4 says the names of an object should be unique and leaves what a
/// reader does with a document where they are not to the reader. Replacing keeps
/// the order and the meaning every other reader gives such a document: the last
/// value written for a name is the value of that name.
fn with_member(
  members : Array[(String, Value)],
  name : String,
  value : Value,
) -> Array[(String, Value)] {
  let mut replaced = false
  for index, pair in members {
    if pair.0 == name {
      members[index] = (name, value)
      replaced = true
    }
  }
  if !replaced {
    members.push((name, value))
  }
  members
}

///|
/// A number, as the digits the document wrote.
///
/// The grammar is RFC 8259 §6 to the letter: no leading plus, no leading zero,
/// a digit on both sides of a decimal point, and an exponent that has digits.
fn number_text() -> @moonpsec.Parser[String] {
  let sign = @moonpsec.char('-').map(_ => "-").or(@moonpsec.pure(""))
  let leading = @moonpsec.char('0')
    .map(_ => "0")
    .or(
      @moonpsec.take_while1(ch => ch >= '0' && ch <= '9').and_then(digits => {
        if digits.unsafe_get(0) == '0' {
          @moonpsec.fail("a number may not start with a zero")
        } else {
          @moonpsec.pure(digits)
        }
      }),
    )
  let fraction = @moonpsec.char('.')
    .then(@moonpsec.take_while1(ch => ch.is_ascii_digit()))
    .map(digits => ".\{digits}")
    .or(@moonpsec.pure(""))
  let exponent_sign = @moonpsec.choice([
    @moonpsec.char('+').map(_ => "+"),
    @moonpsec.char('-').map(_ => "-"),
    @moonpsec.pure(""),
  ])
  let exponent = @moonpsec.satisfy(ch => ch == 'e' || ch == 'E')
    .map(mark => mark.to_string())
    .and_then(mark => {
      exponent_sign.and_then(sign_text => {
        @moonpsec.take_while1(ch => ch.is_ascii_digit()).map(digits => {
          "\{mark}\{sign_text}\{digits}"
        })
      })
    })
    .or(@moonpsec.pure(""))
  sign
  .and_then(negative => {
    leading.and_then(whole => {
      fraction.and_then(part => {
        exponent.map(tail => "\{negative}\{whole}\{part}\{tail}")
      })
    })
  })
  .label("a number")
}

///|
/// A string, with the escapes of RFC 8259 §7.
///
/// A run of plain characters is read by the run rather than a character at a
/// time: a string of a thousand letters is one scan and one state, not a
/// thousand of each.
fn text_value() -> @moonpsec.Parser[String] {
  let plain = @moonpsec.take_while(ch => {
    ch != '"' && ch != '\\' && ch.to_int() >= 0x20
  })
  let escape = @moonpsec.char('\\').then(
    @moonpsec.choice([
      @moonpsec.char('"').map(_ => '"'),
      @moonpsec.char('\\').map(_ => '\\'),
      @moonpsec.char('/').map(_ => '/'),
      @moonpsec.char('b').map(_ => '\u{8}'),
      @moonpsec.char('f').map(_ => '\u{c}'),
      @moonpsec.char('n').map(_ => '\n'),
      @moonpsec.char('r').map(_ => '\r'),
      @moonpsec.char('t').map(_ => '\t'),
      unicode_escape(),
    ]),
  )
  // The escape comes first: it always reads at least two characters, so the
  // run after it either makes progress or ends the string.
  let piece = escape.map(ch => ch.to_string()).or(plain)
  // The opening quote is not followed by skipped whitespace: a space at the
  // start of a string is content, and eating it would change the document.
  @moonpsec.between(
    @moonpsec.char('"'),
    token(@moonpsec.char('"')),
    piece.many(),
  )
  .map(parts => parts.join(""))
  .label("a string")
}

///|
/// `\uXXXX`, with a surrogate pair put back together.
///
/// Half a pair is refused rather than replaced: RFC 8259 §7 allows a document
/// to carry one, and a reader that turned it into U+FFFD would hand back a
/// character the document never contained.
fn unicode_escape() -> @moonpsec.Parser[Char] {
  @moonpsec.char('u')
  .then(hex_quad())
  .and_then(code => {
    if code >= 0xD800 && code <= 0xDBFF {
      @moonpsec.string("\\u")
      .then(hex_quad())
      .and_then(low => {
        if low >= 0xDC00 && low <= 0xDFFF {
          @moonpsec.pure(pair(code, low))
        } else {
          @moonpsec.fail("a high surrogate without the low half of the pair")
        }
      })
    } else if code >= 0xDC00 && code <= 0xDFFF {
      @moonpsec.fail("a low surrogate without the high half of the pair")
    } else {
      @moonpsec.pure(code.unsafe_to_char())
    }
  })
}

///|
fn pair(high : Int32, low : Int32) -> Char {
  (0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)).unsafe_to_char()
}

///|
fn hex_quad() -> @moonpsec.Parser[Int32] {
  let digit = @moonpsec.hex_digit.map(ch => {
    let code = ch.to_int()
    if code <= '9'.to_int() {
      code - '0'.to_int()
    } else if code <= 'F'.to_int() {
      code - 'A'.to_int() + 10
    } else {
      code - 'a'.to_int() + 10
    }
  })
  digit
  .count(4)
  .map(digits => {
    let mut value = 0
    for each in digits {
      value = value * 16 + each
    }
    value
  })
}
