// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The verdict on `text` as a JSON document, as a JSON object for the page.
///
/// A refusal comes back with the four things the library knows: where it
/// happened, what was found, what would have been accepted, and any note the
/// grammar attached.
pub fn verdict(text : String) -> String {
  match @json.parse(text) {
    Ok(value) => {
      let out = StringBuilder()
      out.write_string("{\"ok\":true,\"value\":")
      quote(out, value.to_string())
      out.write_char('}')
      out.to_string()
    }
    Err(refusal) => refusal_json(refusal)
  }
}

///|
/// What the reader makes of `text` cut short at `at`: whether it is waiting for
/// the rest, and what it would say if the text ended right there.
///
/// The page scrubs the cut through a document and draws both answers, which is
/// what incremental reading is: a prefix the reader can be of two minds about.
pub fn cut(text : String, at : Int32) -> String {
  let prefix = prefix_of(text, at)
  let feeder = @moonpsec.feeder(@json.document())
  let mut waiting_more = false
  match feeder.feed(prefix) {
    Needs(_) => waiting_more = true
    _ => ()
  }
  let out = StringBuilder()
  out.write_string("{\"waiting\":")
  out.write_string(if waiting_more { "true" } else { "false" })
  out.write_string(",\"ending\":")
  match @json.parse(prefix) {
    Ok(value) => {
      out.write_string("{\"ok\":true,\"value\":")
      quote(out, value.to_string())
      out.write_char('}')
    }
    Err(refusal) => out.write_string(refusal_json(refusal))
  }
  out.write_char('}')
  out.to_string()
}

///|
/// The arithmetic expression `text` read with a table of operators, as the tree
/// the table built: grouping and precedence are the answer, not a number.
pub fn expression(text : String) -> String {
  match @moonpsec.run(arithmetic, text) {
    Ok(tree) => {
      let out = StringBuilder()
      out.write_string("{\"ok\":true,\"tree\":")
      tree.to_json(out)
      out.write_string(",\"value\":")
      out.write_string(tree.value().to_string())
      out.write_char('}')
      out.to_string()
    }
    Err(refusal) => refusal_json(refusal)
  }
}

///|
/// What the tree is worth. The grammar built it; the arithmetic is the
/// example's, not the library's.
fn Term::value(self : Term) -> Int32 {
  match self {
    Number(value) => value
    Negate(inner) => -inner.value()
    Binary(op, left, right) =>
      match op {
        "+" => left.value() + right.value()
        "-" => left.value() - right.value()
        "*" => left.value() * right.value()
        "/" => left.value() / right.value()
        "^" => {
          let mut result = 1
          for _ in 0..<right.value() {
            result = result * left.value()
          }
          result
        }
        _ => 0
      }
  }
}

///|
/// A node of the tree the operator table builds.
priv enum Term {
  Number(Int32)
  Negate(Term)
  Binary(String, Term, Term)
}

///|
fn Term::to_json(self : Term, out : StringBuilder) -> Unit {
  match self {
    Number(value) => {
      out.write_string("{\"kind\":\"number\",\"value\":")
      out.write_string(value.to_string())
      out.write_char('}')
    }
    Negate(inner) => {
      out.write_string("{\"kind\":\"negate\",\"inner\":")
      inner.to_json(out)
      out.write_char('}')
    }
    Binary(op, left, right) => {
      out.write_string("{\"kind\":\"binary\",\"op\":")
      quote(out, op)
      out.write_string(",\"left\":")
      left.to_json(out)
      out.write_string(",\"right\":")
      right.to_json(out)
      out.write_char('}')
    }
  }
}

///|
/// The grammar the operator demo reads: numbers, brackets, and five operators
/// whose precedence is the order of the table.
let arithmetic : @moonpsec.Parser[Term] = build_arithmetic()

///|
fn build_arithmetic() -> @moonpsec.Parser[Term] {
  let whole : Ref[@moonpsec.Parser[Term]] = Ref(@moonpsec.pure(Number(0)))
  let space = @moonpsec.take_while(ch => ch == ' ' || ch == '\t')
  let number = @moonpsec.take_while1(ch => ch.is_ascii_digit())
    .map(digits => {
      let mut value = 0
      for index in 0..<digits.length() {
        value = value * 10 + (digits.unsafe_get(index).to_int() - '0'.to_int())
      }
      Number(value)
    })
    .label("a number")
  let mark = fn(ch : Char) {
    @moonpsec.char(ch).skip(space).label(ch.to_string())
  }
  let bracket = @moonpsec.between(
    mark('('),
    mark(')'),
    @moonpsec.pure(()).and_then(_ => whole.val),
  )
  let atom = number.or(bracket).skip(space)
  let binary = fn(ch : Char, name : String) {
    mark(ch).map(_ => (left : Term, right : Term) => Binary(name, left, right))
  }
  let negate = mark('-').map(_ => (inner : Term) => Negate(inner))
  let operators : Array[Array[@moonpsec.Operator[Term]]] = [
    [@moonpsec.Operator::Prefix(negate)],
    [@moonpsec.Operator::InfixR(binary('^', "^"))],
    [
      @moonpsec.Operator::InfixL(binary('*', "*")),
      @moonpsec.Operator::InfixL(binary('/', "/")),
    ],
    [
      @moonpsec.Operator::InfixL(binary('+', "+")),
      @moonpsec.Operator::InfixL(binary('-', "-")),
    ],
  ]
  let parsed = space
    .then(@moonpsec.make_expr_parser(atom, operators))
    .skip(space)
  whole.val = parsed
  parsed.eof()
}

///|
fn refusal_json(refusal : @moonpsec.Refused) -> String {
  let out = StringBuilder()
  out.write_string("{\"ok\":false")
  out.write_string(",\"at\":")
  out.write_string(refusal.position.at.to_string())
  out.write_string(",\"line\":")
  out.write_string(refusal.position.line.to_string())
  out.write_string(",\"column\":")
  out.write_string(refusal.position.column.to_string())
  out.write_string(",\"got\":")
  match refusal.got {
    Some(item) => quote(out, item.to_string())
    None => quote(out, "")
  }
  out.write_string(",\"want\":[")
  for index, item in refusal.want {
    if index > 0 {
      out.write_char(',')
    }
    quote(out, item.to_string())
  }
  out.write_string("],\"notes\":[")
  for index, note in refusal.notes {
    if index > 0 {
      out.write_char(',')
    }
    quote(out, note)
  }
  out.write_char(']')
  out.write_char('}')
  out.to_string()
}

///|
/// `text` cut at `at`, without splitting a character in half: the page counts
/// offsets in UTF-16 code units, and a cut inside a pair would be no text at all.
fn prefix_of(text : String, at : Int32) -> StringView {
  let total = text.length()
  let mut end = if at < 0 { 0 } else if at > total { total } else { at }
  if end > 0 && end < total {
    let unit = text.unsafe_get(end - 1)
    if unit.is_leading_surrogate() {
      end += 1
    }
  }
  text.exact_view(start=0, end~)
}

///|
fn quote(out : StringBuilder, text : String) -> Unit {
  out.write_char('"')
  for ch in text {
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if ch.to_int() < 0x20 {
          out.write_string("\\u")
          let digits = "0123456789abcdef"
          for shift in [12, 8, 4, 0] {
            out.write_char(
              digits.unsafe_get((ch.to_int() >> shift) & 0xF).unsafe_to_char(),
            )
          }
        } else {
          out.write_char(ch)
        }
    }
  }
  out.write_char('"')
}
