// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A calculator over single digits: prefix minus, power, product, sum, and
/// parentheses that go back to the whole expression.
fn arithmetic() -> @moonpsec.Parser[Int32] {
  let expression : Ref[@moonpsec.Parser[Int32]] = Ref(@moonpsec.pure(0))
  let nested = @moonpsec.pure(()).and_then(_ => expression.val)
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let atom = number.or(
    @moonpsec.between(@moonpsec.char('('), @moonpsec.char(')'), nested),
  )
  let power = @moonpsec.char('^').map(_ => {
    (a : Int32, b : Int32) => {
      let mut result = 1
      for _ in 0..<b {
        result = result * a
      }
      result
    }
  })
  let product = @moonpsec.char('*').map(_ => (a : Int32, b : Int32) => a * b)
  let quotient = @moonpsec.char('/').map(_ => (a : Int32, b : Int32) => a / b)
  let sum = @moonpsec.char('+').map(_ => (a : Int32, b : Int32) => a + b)
  let difference = @moonpsec.char('-').map(_ => (a : Int32, b : Int32) => a - b)
  let negate = @moonpsec.char('-').map(_ => (a : Int32) => -a)
  let parsed = @moonpsec.make_expr_parser(atom, [
    [@moonpsec.Operator::Prefix(negate)],
    [@moonpsec.Operator::InfixR(power)],
    [@moonpsec.Operator::InfixL(product), @moonpsec.Operator::InfixL(quotient)],
    [@moonpsec.Operator::InfixL(sum), @moonpsec.Operator::InfixL(difference)],
  ])
  expression.val = parsed
  parsed
}

///|
test "a product binds tighter than a sum" {
  assert_eq(@moonpsec.run(arithmetic(), "1+2*3"), Ok(7))
  assert_eq(@moonpsec.run(arithmetic(), "2*3+1"), Ok(7))
}

///|
test "a left associative operator folds to the left" {
  assert_eq(@moonpsec.run(arithmetic(), "8/2/2"), Ok(2))
  assert_eq(@moonpsec.run(arithmetic(), "8-2-3"), Ok(3))
}

///|
test "a right associative operator folds to the right" {
  assert_eq(@moonpsec.run(arithmetic(), "2^3^2"), Ok(512))
}

///|
test "a prefix operator binds tighter than the infix operators of its level" {
  assert_eq(@moonpsec.run(arithmetic(), "-3+4"), Ok(1))
  assert_eq(@moonpsec.run(arithmetic(), "2*-3"), Ok(-6))
}

///|
test "parentheses go back to the whole expression" {
  assert_eq(@moonpsec.run(arithmetic(), "(1+2)*3"), Ok(9))
  assert_eq(@moonpsec.run(arithmetic(), "2*(3+(4-1))"), Ok(12))
}

///|
test "a postfix operator is applied after the term" {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let factorial = @moonpsec.char('!').map(_ => {
    (a : Int32) => {
      let mut result = 1
      for n in 1..<=a {
        result = result * n
      }
      result
    }
  })
  let parser = @moonpsec.make_expr_parser(number, [
    [@moonpsec.Operator::Postfix(factorial)],
  ])
  assert_eq(@moonpsec.run(parser, "4!"), Ok(24))
}

///|
test "a non associative operator refuses a second one" {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let same = @moonpsec.string("==").map(_ => {
    (a : Int32, b : Int32) => if a == b { 1 } else { 0 }
  })
  let parser = @moonpsec.make_expr_parser(number, [
    [@moonpsec.Operator::InfixN(same)],
  ])
  assert_eq(@moonpsec.run(parser, "1==1"), Ok(1))
  let error = @moonpsec.run(parser, "1==1==1").unwrap_err()
  assert_eq(error.notes, ["ambiguous use of a non-associative operator"])
}

///|
test "a ternary operator reads both of its separators" {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let then : @moonpsec.Parser[@moonpsec.Parser[(Int32, Int32, Int32) -> Int32]] = @moonpsec.char(
    '?',
  ).map(_ => {
    @moonpsec.char(':').map(_ => {
      (when : Int32, yes : Int32, no : Int32) => {
        if when != 0 {
          yes
        } else {
          no
        }
      }
    })
  })
  let parser = @moonpsec.make_expr_parser(number, [
    [@moonpsec.Operator::Ternary(then)],
  ])
  assert_eq(@moonpsec.run(parser, "1?2:3"), Ok(2))
  assert_eq(@moonpsec.run(parser, "0?2:3"), Ok(3))
}

///|
test "a ternary operator groups to the right" {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let then : @moonpsec.Parser[@moonpsec.Parser[(Int32, Int32, Int32) -> Int32]] = @moonpsec.char(
    '?',
  ).map(_ => {
    @moonpsec.char(':').map(_ => {
      (when : Int32, yes : Int32, no : Int32) => {
        if when != 0 {
          yes
        } else {
          no
        }
      }
    })
  })
  let parser = @moonpsec.make_expr_parser(number, [
    [@moonpsec.Operator::Ternary(then)],
  ])
  assert_eq(@moonpsec.run(parser, "0?1:0?2:3"), Ok(3))
}

///|
test "a table with no entry for an operator reads only the term" {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let parser = @moonpsec.make_expr_parser(number, [])
  assert_eq(@moonpsec.run(parser, "7"), Ok(7))
}

///|
test "an expression that stops in the middle points at the operand" {
  let error = @moonpsec.run(arithmetic(), "1+").unwrap_err()
  assert_eq(error.position.at, 2)
  assert_eq(error.got, Some(@moonpsec.Item::End))
}

///|
test "an operator that matched and then found no operand is a refusal" {
  let error = @moonpsec.run(arithmetic(), "1+*2").unwrap_err()
  assert_eq(error.position.at, 2)
  assert_eq(error.got, Some(@moonpsec.Item::Token('*')))
}

///|
test "operators at the same precedence share one chain" {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let sum = @moonpsec.char('+').map(_ => (a : Int32, b : Int32) => a + b)
  let difference = @moonpsec.char('-').map(_ => (a : Int32, b : Int32) => a - b)
  let parser = @moonpsec.make_expr_parser(number, [
    [@moonpsec.Operator::InfixL(sum), @moonpsec.Operator::InfixL(difference)],
  ])
  assert_eq(@moonpsec.run(parser, "9-2+1"), Ok(8))
}

///|
test "a chain of a thousand terms does not run out of stack" {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let sum = @moonpsec.char('+').map(_ => (a : Int32, b : Int32) => a + b)
  let parser = @moonpsec.make_expr_parser(number, [
    [@moonpsec.Operator::InfixL(sum)],
  ])
  let text = StringBuilder()
  for index in 0..<1000 {
    if index > 0 {
      text.write_char('+')
    }
    text.write_char('1')
  }
  assert_eq(@moonpsec.run(parser, text.to_string()).unwrap(), 1000)
}

///|
test "a right associative chain of a thousand terms does not run out of stack" {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let keep = @moonpsec.char('^').map(_ => (_ : Int32, b : Int32) => b)
  let parser = @moonpsec.make_expr_parser(number, [
    [@moonpsec.Operator::InfixR(keep)],
  ])
  let text = StringBuilder()
  for index in 0..<1000 {
    if index > 0 {
      text.write_char('^')
    }
    text.write_char('1')
  }
  assert_eq(@moonpsec.run(parser, text.to_string()).unwrap(), 1)
}
