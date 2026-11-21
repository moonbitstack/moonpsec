// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One operator in a precedence table.
///
/// An operator is a parser for the operator itself, not a name to look up: a
/// grammar that wants `+` to mean something different in a string context
/// passes a different parser, and one that wants operators separated from
/// their operands by space passes a parser that eats the space.
///
/// `Ternary` reads its first separator and produces a parser for its second,
/// which is what lets `a ? b : c` be written with the colon only after the
/// middle operand has been read — the reference shape for a conditional.
pub(all) enum Operator[T] {
  ///
  /// An infix operator that groups to the left: `1-2-3` is `(1-2)-3`.
  InfixL(Parser[(T, T) -> T])
  ///
  /// An infix operator that groups to the right: `2^3^2` is `2^(3^2)`.
  InfixR(Parser[(T, T) -> T])
  ///
  /// An infix operator that does not group at all: `a == b == c` is a
  /// mistake, and saying so is more useful than picking a side.
  InfixN(Parser[(T, T) -> T])
  ///
  /// An operator written before its operand.
  Prefix(Parser[(T) -> T])
  ///
  /// An operator written after its operand.
  Postfix(Parser[(T) -> T])
  ///
  /// A right-associative ternary operator: the first parser reads the first
  /// separator and produces a parser for the second.
  Ternary(Parser[Parser[(T, T, T) -> T]])
}

///|
/// Builds an expression parser from a term parser and a table of operators.
///
/// The table is ordered by precedence, highest first; every operator in one
/// entry has the same precedence. A prefix or postfix operator binds tighter
/// than any infix operator of the same entry, and two unary operators of the
/// same entry are not allowed in a row, so `--1` is a refusal rather than a
/// double negation — a grammar that wants the latter wraps the operator in
/// `many` itself.
///
/// ```mbt check
/// test {
///   let number = @moonpsec.satisfy(ch => ch >= '0' && ch <= '9').map(ch => {
///     ch.to_int() - '0'.to_int()
///   })
///   let plus = @moonpsec.char('+').map(_ => (a : Int32, b : Int32) => a + b)
///   let times = @moonpsec.char('*').map(_ => (a : Int32, b : Int32) => a * b)
///   let expr = @moonpsec.make_expr_parser(number, [
///     [@moonpsec.Operator::InfixL(times)],
///     [@moonpsec.Operator::InfixL(plus)],
///   ])
///   assert_eq(@moonpsec.run(expr, "1+2*3"), Ok(7))
/// }
/// ```
pub fn[T] make_expr_parser(
  term : Parser[T],
  table : Array[Array[Operator[T]]],
) -> Parser[T] {
  let mut parser = term
  for level in table {
    parser = add_level(parser, level)
  }
  parser
}

///|
/// Adds one entry of the table to a term parser.
fn[T] add_level(term : Parser[T], ops : Array[Operator[T]]) -> Parser[T] {
  let right = []
  let left = []
  let none = []
  let before = []
  let after = []
  let ternary = []
  for op in ops {
    match op {
      InfixR(parse) => right.push(parse)
      InfixL(parse) => left.push(parse)
      InfixN(parse) => none.push(parse)
      Prefix(parse) => before.push(parse)
      Postfix(parse) => after.push(parse)
      Ternary(parse) => ternary.push(parse)
    }
  }
  let prefix = if before.is_empty() {
    pure(unary_identity)
  } else {
    choice(before).or_else(unary_identity)
  }
  let postfix = if after.is_empty() {
    pure(unary_identity)
  } else {
    choice(after).or_else(unary_identity)
  }
  let operand = prefix.and_then(pre => {
    term.and_then(value => postfix.map(post => post(pre(value))))
  })
  operand.and_then(value => {
    chain_right(choice(right), operand, value)
    .or(chain_left(choice(left), operand, value))
    .or(chain_none(choice(none), operand, value))
    .or(chain_ternary(choice(ternary), operand, value))
    .or(pure(value))
  })
}

///|
fn[T] unary_identity(value : T) -> T {
  value
}

///|
/// Folds `x op1 y1 op2 y2 ...` to the left. Iterative, because a table of
/// thousands of terms is a document, not a recursion depth.
fn[T] chain_left(
  op : Parser[(T, T) -> T],
  operand : Parser[T],
  first : T,
) -> Parser[T] {
  op.and_then(combine => {
    operand.and_then(right => {
      Parser::new(fn(st) {
        let mut value = combine(first, right)
        let mut at = st
        while true {
          match op.apply(at) {
            Value(next, after_op) =>
              match operand.apply(after_op) {
                Value(more, after_more) => {
                  value = next(value, more)
                  at = after_more
                }
                Problem(error, _) => return Problem(error, true)
                Starved(need) => return Starved(need)
              }
            Problem(error, consumed) =>
              if consumed {
                return Problem(error, true)
              } else {
                break
              }
            Starved(need) => return Starved(need)
          }
        }
        Value(value, at)
      })
    })
  })
}

///|
/// Folds `x op1 y1 op2 y2 ...` to the right, collecting the chain first so
/// that its length costs no stack.
fn[T] chain_right(
  op : Parser[(T, T) -> T],
  operand : Parser[T],
  first : T,
) -> Parser[T] {
  op.and_then(combine => {
    operand.and_then(second => {
      Parser::new(fn(st) {
        let values = [first, second]
        let combines = [combine]
        let mut at = st
        while true {
          match op.apply(at) {
            Value(next, after_op) =>
              match operand.apply(after_op) {
                Value(more, after_more) => {
                  combines.push(next)
                  values.push(more)
                  at = after_more
                }
                Problem(error, _) => return Problem(error, true)
                Starved(need) => return Starved(need)
              }
            Problem(error, consumed) =>
              if consumed {
                return Problem(error, true)
              } else {
                break
              }
            Starved(need) => return Starved(need)
          }
        }
        let mut value = values[values.length() - 1]
        let mut index = values.length() - 2
        while index >= 0 {
          value = combines[index](values[index], value)
          index -= 1
        }
        Value(value, at)
      })
    })
  })
}

///|
/// Applies a non-associative operator once, and refuses a second one of the
/// same entry: `a == b == c` says which side it would have to pick, and no
/// answer is right.
fn[T] chain_none(
  op : Parser[(T, T) -> T],
  operand : Parser[T],
  first : T,
) -> Parser[T] {
  op.and_then(combine => {
    operand.and_then(right => {
      Parser::new(fn(st) {
        match op.apply(st) {
          Value(_, _) =>
            Problem(
              {
                position: st.position(),
                got: Some(found(st)),
                want: [],
                notes: ["ambiguous use of a non-associative operator"],
              },
              false,
            )
          Problem(_, _) => Value(combine(first, right), st)
          Starved(need) => Starved(need)
        }
      })
    })
  })
}

///|
/// Reads `a ? b : c ? d : e` as `a ? b : (c ? d : e)`.
fn[T] chain_ternary(
  separation : Parser[Parser[(T, T, T) -> T]],
  operand : Parser[T],
  first : T,
) -> Parser[T] {
  separation.and_then(second => {
    let middle = operand.and_then(mid => {
      chain_ternary(separation, operand, mid).or(pure(mid))
    })
    middle.and_then(center => {
      second.and_then(combine => {
        let last = operand.and_then(rest => {
          chain_ternary(separation, operand, rest).or(pure(rest))
        })
        last.map(right => combine(first, center, right))
      })
    })
  })
}
