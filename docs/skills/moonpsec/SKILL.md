---
name: moonpsec
description: "Parser combinators for MoonBit: read a grammar out of text with line and column errors, explicit backtracking, operator precedence tables and incremental input. Use when a task needs to parse a file format, a language, a protocol message or any structured text, or when an error message has to say what was expected where."
---

# moonpsec

A parser is a value. Small parsers are combined into a grammar, and a refusal
carries the line, the column and everything that would have been accepted at
that place.

## Install

```moonbit
// moon.mod
import {
  "moonbitstack/moonpsec@0.1.0",
}
```

```moonbit
// a file in the package that uses it
import {
  "moonbitstack/moonpsec",
}
```

## Read a small format

`take_while1` reads a run of characters, `and_then` decides what follows from
what came before, and `run` requires the whole text to be described.

```moonbit
test {
  let key = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic())
  let value = @moonpsec.take_while1(ch => ch.is_ascii_digit())
  let pair = key.and_then(name => @moonpsec.char('=').then(value).map(number => (name, number)))
  let config = pair.sep_by(@moonpsec.char(','))
  let (entries, _) = @moonpsec.parse(config, "a=1,b=22").unwrap()
  assert_eq(entries.length(), 2)
  assert_eq(entries[1].0, "b")
}
```

## Report what was expected

`label` replaces the character classes in a message with the reader's word, and
`pretty` renders the refusal with the line it happened on.

```moonbit
test {
  let integer = @moonpsec.take_while1(ch => ch.is_ascii_digit()).label("integer")
  let assignment = @moonpsec.char('=').then(integer)
  let refusal = @moonpsec.run(assignment, "=x").unwrap_err()
  assert_eq(refusal.to_string(), "1:2: unexpected 'x'; expecting integer")
  assert_eq(refusal.pretty("=x").starts_with("1:2:"), true)
}
```

## Precedence from a table

`make_expr_parser` builds an expression parser from a term parser and a table of
operators, ordered from the tightest binding to the loosest.

```moonbit
test {
  let number = @moonpsec.take_while1(ch => ch.is_ascii_digit()).map(digits => {
    let mut value = 0
    for index in 0..<digits.length() {
      value = value * 10 + (digits.unsafe_get(index).to_int() - '0'.to_int())
    }
    value
  })
  let times = @moonpsec.char('*').map(_ => (a : Int, b : Int) => a * b)
  let plus = @moonpsec.char('+').map(_ => (a : Int, b : Int) => a + b)
  let table : Array[Array[@moonpsec.Operator[Int]]] = [
    [@moonpsec.Operator::InfixL(times)],
    [@moonpsec.Operator::InfixL(plus)],
  ]
  let expression = @moonpsec.make_expr_parser(number, table)
  assert_eq(@moonpsec.run(expression, "2+3*4"), Ok(14))
}
```

## Rules that catch people out

- **A choice commits once it has read something.** `string("ab").or(string("ac"))`
  never tries the second branch on `ac`: the first read `a`. Wrap the branch in
  `attempt()` when the other one should be tried anyway.
- **`many` stops at the first refusal, but not always quietly.** A round that
  reads something and then refuses fails the whole repetition. `sep_by` therefore
  refuses a trailing separator; `sep_end_by` is the one that reads one.
- **`label` and `hidden` only speak about a refusal that read nothing.** A parser
  that has already consumed text keeps the message of the character that broke it.
- **`run` requires the whole text.** Use `run_partial` for a value at the start of
  a longer text, or `parse` when the position it stopped at matters.
- **`take_while` scans a run in one pass.** Building a run character by character
  with `many` works but costs an allocation per character; prefer `take_while`.
- **A recursive grammar needs a `Ref`.** Build the parser for the nested case as
  `pure(()).and_then(_ => holder.val)` and assign the finished parser to the
  holder afterwards; a `let` that refers to itself does not exist yet.
- **Text that arrives in pieces goes to a `Feeder`.** `feed` answers `Needs`
  while the text ends in the middle of something; a grammar that has no `eof`
  answers as soon as it has a value, and the rest comes back with it.
