# moonpsec

Parser combinators for MoonBit. A parser is a value; a grammar is built by
combining small parsers into larger ones; a refusal names the line, the column,
and everything that would have been accepted at that place.

```moonbit
test {
  let digits = @moonpsec.take_while1(ch => ch.is_ascii_digit())
  assert_eq(@moonpsec.run(digits, "42"), Ok("42"))
}
```

[mooncakes](https://mooncakes.io/docs/moonbitstack/moonpsec) ·
[guide](#guide) · [interface](#interface) · [errors](#errors) ·
[operators](#operator-tables) · [streaming](#text-that-arrives-in-pieces) ·
[examples](#examples)

## Add it

```moonbit
// moon.mod
import {
  "moonbitstack/moonpsec@0.1.0",
}
```

## Guide

### A first grammar

A parser reads characters and produces a value. `char` reads one character,
`string` a run of them, and the methods on a parser build the rest: `map` to
change the value, `and_then` to decide what follows, `or` to offer a choice.

```moonbit
test {
  let keyword = @moonpsec.string("let")
  let name = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic())
  let binding = keyword.then(@moonpsec.space1.then(name)).skip(@moonpsec.char(';'))
  assert_eq(@moonpsec.run(binding, "let answer;"), Ok("answer"))
}
```

### Three ways to run one

`run` reads the whole text and refuses anything left over; `run_partial` hands
back the text it did not read; `parse` also says where the parser stopped.

```moonbit
test {
  let word = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic())
  assert_eq(@moonpsec.run(word, "abc"), Ok("abc"))
  assert_eq(@moonpsec.run_partial(word, "abc123").unwrap().1.to_owned(), "123")
  let (_, end) = @moonpsec.parse(word, "abc").unwrap()
  assert_eq(end.column, 4)
}
```

### Repetition

`many` reads as often as it can, `many1` at least once, `count` a fixed number
of times, `sep_by` between separators. A list that may end with a separator
wants `sep_end_by`.

```moonbit
test {
  let item = @moonpsec.take_while1(ch => ch != ',')
  let list = item.sep_by(@moonpsec.char(','))
  assert_eq(@moonpsec.run(list, "a,b,c").unwrap().length(), 3)
  let trailing = item.sep_end_by(@moonpsec.char(','))
  assert_eq(@moonpsec.run(trailing, "a,b,").unwrap().length(), 2)
}
```

### Backtracking

A choice is not a search. Once a branch has read something it has committed to
its reading, and a later mistake is reported instead of being retried another
way. `attempt` is how a grammar says the other branch should be tried anyway.

```moonbit
test {
  let committed = @moonpsec.string("ab").or(@moonpsec.string("ac"))
  assert_eq(@moonpsec.run(committed, "ac").to_option() is None, true)
  let retried = @moonpsec.string("ab").attempt().or(@moonpsec.string("ac"))
  assert_eq(@moonpsec.run(retried, "ac"), Ok("ac"))
}
```

The rule is what makes a grammar predictable: without it, every alternative is
tried at every position, and the error of a document names the last alternative
rather than the one the grammar meant.

### Looking without reading

`look_ahead` matches and puts the position back; `not_followed_by` succeeds only
when its parser fails. Together they read a keyword that may not be the start of
a longer word.

```moonbit
test {
  let keyword = @moonpsec.string("if").skip(@moonpsec.alpha_num.not_followed_by())
  assert_eq(@moonpsec.run_partial(keyword, "if(").unwrap().0, "if")
  assert_eq(@moonpsec.run(keyword, "iffy").to_option() is None, true)
}
```

### Naming what was wanted

A refusal built out of character classes says `expecting digit`. `label` puts
the reader's word in its place, and `hidden` takes the expectations away
entirely for a branch that exists only to be tried.

```moonbit
test {
  let integer = @moonpsec.digit.many1().map(digits => digits.length()).label("integer")
  let refusal = @moonpsec.run(integer, "+").unwrap_err()
  assert_eq(refusal.to_string(), "1:1: unexpected '+'; expecting integer")
}
```

## Errors

A refusal carries where it happened, what was found, what was wanted, and any
message the grammar attached with `fail`. `to_string` is the one-line form for a
log; `pretty` is the form for a person.

```moonbit
test {
  let refusal = @moonpsec.run(@moonpsec.string("let"), "lex").unwrap_err()
  assert_eq(refusal.position.line, 1)
  assert_eq(refusal.position.column, 3)
  assert_eq(refusal.want.length(), 1)
  assert_eq(
    refusal.pretty("lex"),
    "1:3:\n  |\n1 | lex\n  |   ^\nunexpected 'x'\nexpecting \"let\"",
  )
}
```

A choice merges the refusals of its branches: at the same place the expected
items of both are kept, and a branch that got further is the one reported.

```moonbit
test {
  let one = @moonpsec.char('a').map(ch => ch.to_string())
  let two = @moonpsec.char('b').map(ch => ch.to_string())
  let choice = one.or(two).or(@moonpsec.string("cd"))
  let refusal = @moonpsec.run(choice, "z").unwrap_err()
  assert_eq(refusal.want.length(), 3)
  assert_eq(refusal.to_string(), "1:1: unexpected 'z'; expecting 'a', 'b', or \"cd\"")
}
```

### Getting past a refusal

`recover_with` runs a parser and, when it refuses, runs another one at the place
the refusal points at. The value comes back with the refusal beside it, so a
caller can report several problems and still read the rest of the document.

```moonbit
test {
  let digit = @moonpsec.digit.label("digit")
  let forgiving = digit.recover_with(_ => @moonpsec.any_char.map(_ => '0'))
  let repairs = @moonpsec.run(forgiving.many(), "1x2").unwrap()
  assert_eq(repairs.length(), 3)
  assert_eq(repairs[1].value, '0')
  assert_eq(repairs[1].refusal is Some(_), true)
}
```

## Operator tables

`make_expr_parser` turns a term parser and a table of operators into an
expression parser. The table is ordered from the operator that binds tightest to
the one that binds loosest.

```moonbit
test {
  let number = @moonpsec.digit.map(ch => ch.to_int() - '0'.to_int())
  let times = @moonpsec.char('*').map(_ => (a : Int, b : Int) => a * b)
  let plus = @moonpsec.char('+').map(_ => (a : Int, b : Int) => a + b)
  let minus = @moonpsec.char('-').map(_ => (a : Int, b : Int) => a - b)
  let power = @moonpsec.char('^').map(_ => (a : Int, b : Int) => {
    let mut result = 1
    for _ in 0..<b {
      result = result * a
    }
    result
  })
  let table : Array[Array[@moonpsec.Operator[Int]]] = [
    [@moonpsec.Operator::InfixR(power)],
    [@moonpsec.Operator::InfixL(times)],
    [@moonpsec.Operator::InfixL(plus), @moonpsec.Operator::InfixL(minus)],
  ]
  let expression = @moonpsec.make_expr_parser(number, table)
  assert_eq(@moonpsec.run(expression, "2^3^2"), Ok(512))
  assert_eq(@moonpsec.run(expression, "8-2-3"), Ok(3))
  assert_eq(@moonpsec.run(expression, "1+2*3"), Ok(7))
}
```

A right-associative operator folds to the right, a left-associative one to the
left, and a non-associative one refuses a second use at the same level instead
of picking a side. Prefix and postfix operators of a level bind tighter than its
infix operators.

## Text that arrives in pieces

A `Feeder` takes the text a chunk at a time. When the text ends in the middle of
something, it asks for more; when it has enough it hands back the value and the
text it did not read.

```moonbit
test {
  let feeder = @moonpsec.feeder(@moonpsec.string("hello").eof())
  assert_eq(feeder.feed("he") is @moonpsec.Progress::Needs(_), true)
  assert_eq(feeder.feed("llo") is @moonpsec.Progress::Needs(_), true)
  assert_eq(feeder.finish().unwrap(), "hello")
}
```

A grammar that describes a prefix of the text — one without `eof` — is answered
as soon as it has what it needs, and the rest of the chunk comes back with the
value. The whole text is kept while it arrives, so a document fed in a few
kilobyte-sized chunks costs a few runs; feeding it a byte at a time would cost a
run per byte.

## Interface

### Reading text

| Function | Reads |
|:--|:--|
| `run(parser, text)` | A value from the whole text, refusing anything left over |
| `run_partial(parser, text)` | A value and the text that was not read |
| `run_position(parser, text)` | A value and the position it stopped at |
| `parse(parser, text)` | The same, from the whole text |
| `stream(parser, chunks)` | The same, from text that arrives in pieces |
| `feeder(parser)` | A `Feeder` to push chunks into |

`tab` sets how a tab advances the column, and defaults to 8, the stop every
terminal and editor uses.

### Parsers that read one character

`any_char`, and with `satisfy(check)` any character a predicate accepts.
`char(ch)`, `char_ci(ch)`, `one_of(set)`, `none_of(set)`.

Ready-made classes: `digit`, `hex_digit`, `oct_digit`, `letter`, `alpha_num`,
`space`, `space1`, `blank`, `newline`, `crlf`, `tab`, `upper`, `lower`,
`control`, `printable`, `ascii`, `punctuation`.

### Parsers that read text

| Parser | Reads |
|:--|:--|
| `string(text)` | That exact run |
| `string_ci(text)` | The same run in either ASCII case |
| `take_while(check)` | Characters while the predicate holds, possibly none |
| `take_while1(check)` | The same, but at least one |
| `take(n)` | Exactly `n` characters |
| `take_rest` | Everything that is left |
| `eof` | Nothing, and only at the end |
| `at_end` | Nothing; answers whether the text has ended |

### Combinators

| Function | Does |
|:--|:--|
| `map(f)` | Changes the value |
| `and_then(f)` | Uses a value to choose the parser that follows |
| `then(other)` | Both in order, keeping the second value |
| `skip(other)` | Both in order, keeping the first value |
| `or(other)` | The first that matches |
| `choice(parsers)` | The first of several that matches |
| `attempt()` | Puts the position back when the parser refuses |
| `look_ahead()` | Matches and puts the position back |
| `not_followed_by()` | Succeeds only when the parser refuses |
| `optional()` | The value, or nothing |
| `or_else(value)` | The value, or a given one |
| `many()` | Zero or more, as an array |
| `many1()` | One or more |
| `skip_many()`, `skip_many1()` | The same, discarding the values |
| `count(n)` | Exactly `n` times |
| `sep_by(separator)` | Between separators, zero or more |
| `sep_by1(separator)` | Between separators, at least one |
| `sep_end_by(separator)` | With a separator after each, zero or more |
| `sep_end_by1(separator)` | The same, at least one |
| `many_till(stop)` | Until `stop` matches |
| `chain_left(op)`, `chain_right(op)` | Fold a run of values with an operator |
| `between(open, close, inner)` | An inner parser inside delimiters |
| `label(name)` | Names what the parser wanted, for the message |
| `hidden()` | Takes the expectations away |
| `recover_with(handler)` | Runs a parser at the place of a refusal |
| `eof()` | Requires the text to end after the parser |

### Building parsers

`pure(value)` always produces a value; `fail(message)` always refuses with a
message; `position` produces the place the parser has reached.

## Types

`Parser[T]` is the parser. `Position` is `at`, `line` and `column`, counting the
offset in UTF-16 code units and the line and column from one. `Refused` is the
refusal: its `position`, the item `got`, the items `want`, and any `notes`.
`Repair[T]` is a value a recovered parser produced and the refusal it got past.

## Consistency

The JSON reader in `src/examples/01-json` is checked against JSONTestSuite, the
corpus of documents that a reader must accept, must refuse, or may answer either
way: **318 files, 106 accepted, 212 refused, every one reaching the verdict the
suite asks for**. The choices the suite leaves to the reader are stated in
`scripts/gen_json_suite.py`, which generates the table the check reads.

The behavior is checked against the test suites of the two mature
implementations of this interface in another language: every case of theirs that
applies to this interface is transcribed and passes, and the cases that do not
apply are about what this library does not have — a monad transformer stack,
byte streams, and error hints. **145 tests** run in this package; beside the
transcribed ones they cover what this library adds, such as characters above the
basic plane, tab stops, a chain of a thousand terms, a text split at every
boundary a scan can stop at, and every line of a rendered refusal.

## Examples

`src/examples/01-json` reads JSON with the library: a value type that keeps a
number as the digits it was written with, a grammar for RFC 8259, and the depth
limit that turns a document of a hundred thousand brackets into a refusal.

```
moon run src/examples/01-json
```

`src/examples/02-calc` is a calculator whose precedence comes from a table
rather than from a function per level: `!` binds tightest, then unary minus,
then `^`, then `*` and `/`, then `+` and `-`.

```
moon run src/examples/02-calc
```

## License

Apache-2.0.
