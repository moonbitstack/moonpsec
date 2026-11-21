// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads a few expressions, prints what each one is worth, and then prints the
/// refusal a broken one earns.
///
///     moon run src/examples/02-calc
#coverage.skip
fn main {
  let lines = [
    "1 + 2 * 3", "(1 + 2) * 3", "2 ^ 3 ^ 2", "-4 + 10", "10 / 4", "4! + 1", "1 + 2 *",
  ]
  for line in lines {
    match @moonpsec.run(expression, line) {
      Ok(value) => println("\{line} = \{value}")
      Err(refusal) => {
        println("\{line} was refused")
        println(refusal.pretty(line))
      }
    }
  }
}

///|
/// An expression: numbers, parentheses, and the operators of the table below,
/// with spaces allowed anywhere between them.
///
/// The table is written from the operator that binds tightest to the one that
/// binds loosest, which is how a reader thinks of them; the parser is built
/// from the bottom of that list up, so `+` ends up the outermost chain.
let expression : @moonpsec.Parser[Int32] = build()

///|
fn build() -> @moonpsec.Parser[Int32] {
  let whole : Ref[@moonpsec.Parser[Int32]] = Ref(@moonpsec.pure(0))
  let space = @moonpsec.take_while(ch => ch == ' ' || ch == '\t')
  let number = @moonpsec.take_while1(ch => ch.is_ascii_digit())
    .map(digits => {
      let mut value = 0
      for index in 0..<digits.length() {
        value = value * 10 + (digits.unsafe_get(index).to_int() - '0'.to_int())
      }
      value
    })
    .skip(space)
  let mark = fn(ch : Char) {
    @moonpsec.char(ch).skip(space).label(ch.to_string())
  }
  let bracket = @moonpsec.between(
    mark('('),
    mark(')'),
    @moonpsec.pure(()).and_then(_ => whole.val),
  )
  let atom = number.or(bracket).label("a number or a parenthesised expression")
  let factorial = mark('!').map(_ => {
    (value : Int32) => {
      let mut product = 1
      for each in 2..<=value {
        product = product * each
      }
      product
    }
  })
  let power = mark('^').map(_ => {
    (base : Int32, exponent : Int32) => {
      let mut result = 1
      for _ in 0..<exponent {
        result = result * base
      }
      result
    }
  })
  let times = mark('*').map(_ => (left : Int32, right : Int32) => left * right)
  let over = mark('/').map(_ => (left : Int32, right : Int32) => left / right)
  let plus = mark('+').map(_ => (left : Int32, right : Int32) => left + right)
  let minus = mark('-').map(_ => (left : Int32, right : Int32) => left - right)
  let negate = mark('-').map(_ => (value : Int32) => -value)
  let operators : Array[Array[@moonpsec.Operator[Int32]]] = [
    [@moonpsec.Operator::Postfix(factorial)],
    [@moonpsec.Operator::Prefix(negate)],
    [@moonpsec.Operator::InfixR(power)],
    [@moonpsec.Operator::InfixL(times), @moonpsec.Operator::InfixL(over)],
    [@moonpsec.Operator::InfixL(plus), @moonpsec.Operator::InfixL(minus)],
  ]
  // The parentheses go back to the expression without the end-of-text
  // requirement; only the outermost parser asks for the end.
  let parsed = space
    .then(@moonpsec.make_expr_parser(atom, operators))
    .skip(space)
  whole.val = parsed
  parsed.eof()
}
