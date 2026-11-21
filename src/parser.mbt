// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a parser says when it is run: it has a value and the state it left,
/// it refuses the text, or it cannot tell yet because the text it was given
/// ends where it wanted to look.
///
/// The flag on a refusal is whether the parser had already read something.
/// A choice only falls through to its other branch when nothing was read,
/// which is the rule that makes a grammar predictable: once a parser has
/// committed to an interpretation, a later mistake is reported instead of
/// being quietly retried another way. [`Parser::attempt`] is how a grammar
/// says it wants the other branch tried anyway.
pub enum Reply[T] {
  Value(T, State)
  Problem(Refused, Bool)
  Starved(Int32)
}

///|
/// A parser for values of type `T`.
///
/// A `Parser` is a description, not a run: it can be run any number of times,
/// on any text, and combining two of them with [`Parser::and_then`] or
/// [`Parser::or`] builds a third without touching either.
pub struct Parser[T] {
  rule : (State) -> Reply[T]
}

///|
fn[T] Parser::new(rule : (State) -> Reply[T]) -> Parser[T] {
  { rule, }
}

///|
fn[T] Parser::apply(self : Parser[T], st : State) -> Reply[T] {
  (self.rule)(st)
}

///|
/// A parser that always produces the same value and reads nothing.
pub fn[T] pure(value : T) -> Parser[T] {
  Parser::new(st => Value(value, st))
}

///|
/// A parser that always refuses, saying why. Nothing is read, so a choice
/// still tries its other branch.
pub fn[T] fail(message : String) -> Parser[T] {
  Parser::new(st => {
    Problem(
      { position: st.position(), got: None, want: [], notes: [message], },
      false,
    )
  })
}

///|
/// The position the parser has reached, without reading anything.
pub let position : Parser[Position] = Parser::new(st => Value(st.position(), st))

///|
/// Maps the value of a parser.
///
/// ```mbt check
/// test {
///   let answer = @moonpsec.string("yes").map(s => s.length())
///   assert_eq(@moonpsec.run(answer, "yes"), Ok(3))
/// }
/// ```
pub fn[T, U] Parser::map(self : Parser[T], transform : (T) -> U) -> Parser[U] {
  Parser::new(st => {
    match self.apply(st) {
      Value(value, after) => Value(transform(value), after)
      Problem(error, consumed) => Problem(error, consumed)
      Starved(need) => Starved(need)
    }
  })
}

///|
/// Uses the value of one parser to decide what to parse next.
///
/// The second parser starts where the first one stopped, so a length prefix
/// or an opening tag can decide what has to follow it.
pub fn[T, U] Parser::and_then(
  self : Parser[T],
  next : (T) -> Parser[U],
) -> Parser[U] {
  Parser::new(st => {
    match self.apply(st) {
      Value(value, after) => next(value).apply(after)
      Problem(error, consumed) => Problem(error, consumed)
      Starved(need) => Starved(need)
    }
  })
}

///|
/// Runs both parsers in order and keeps the second value, for the punctuation
/// and keywords a grammar has to read but does not want in its result.
pub fn[T, U] Parser::then(self : Parser[T], next : Parser[U]) -> Parser[U] {
  self.and_then(_ => next)
}

///|
/// Runs both parsers in order and keeps the first value.
pub fn[T, U] Parser::skip(self : Parser[T], next : Parser[U]) -> Parser[T] {
  self.and_then(keep => next.map(_ => keep))
}

///|
/// Replaces whatever the parser expected with one name.
///
/// Without a label the message of a failed `many1(digit)` names the character
/// class; with one it says `expecting integer`, which is what the reader of
/// the document needs to know.
pub fn[T] Parser::label(self : Parser[T], name : String) -> Parser[T] {
  Parser::new(st => {
    match self.apply(st) {
      Value(value, after) => Value(value, after)
      Problem(error, consumed) =>
        Problem({ ..error, want: [Item::Label(name)], }, consumed)
      Starved(need) => Starved(need)
    }
  })
}

///|
/// Drops the expectations of a parser, so that a choice reports only the
/// branches that were meant to be visible.
pub fn[T] Parser::hidden(self : Parser[T]) -> Parser[T] {
  Parser::new(st => {
    match self.apply(st) {
      Value(value, after) => Value(value, after)
      Problem(error, consumed) => Problem({ ..error, want: [], }, consumed)
      Starved(need) => Starved(need)
    }
  })
}

///|
/// Runs the parser and then requires the text to end.
///
/// ```mbt check
/// test {
///   assert_eq(@moonpsec.run(@moonpsec.any_char, "a"), Ok('a'))
/// }
/// ```
pub fn[T] Parser::eof(self : Parser[T]) -> Parser[T] {
  self.skip(eof)
}

///|
/// Runs a parser and then sets aside whether it succeeded.
///
/// A refused parser is always safe to run over: the text is left where it was,
/// which is what makes a sequence of optional clauses possible.
pub fn[T] Parser::attempt(self : Parser[T]) -> Parser[T] {
  Parser::new(st => {
    match self.apply(st) {
      Value(value, after) => Value(value, after)
      Problem(error, _) => Problem(error, false)
      Starved(need) => Starved(need)
    }
  })
}

///|
/// Runs a parser and then puts the position back, keeping its value.
///
/// A `look_ahead` never reads: whatever it matched is still there for the
/// parser that follows, which is how one parser checks what comes next
/// without taking it.
pub fn[T] Parser::look_ahead(self : Parser[T]) -> Parser[T] {
  Parser::new(st => {
    match self.apply(st) {
      Value(value, _) => Value(value, st)
      Problem(error, consumed) => Problem(error, consumed)
      Starved(need) => Starved(need)
    }
  })
}

///|
/// Succeeds, reading nothing, exactly when the parser fails.
///
/// The refusal of the inner parser becomes an expectation of nothing at all;
/// what it matched becomes the surprising thing. `not_followed_by(keyword)`
/// is how a grammar says "an identifier, but not a reserved word".
pub fn[T] Parser::not_followed_by(self : Parser[T]) -> Parser[Unit] {
  Parser::new(fn(st) {
    match self.apply(st) {
      Value(_, _) =>
        Problem(
          {
            position: st.position(),
            got: Some(found(st)),
            want: [],
            notes: [],
          },
          false,
        )
      Problem(_, _) => Value((), st)
      Starved(need) => Starved(need)
    }
  })
}

///|
/// What a reader would call the thing at the current position: the character,
/// or the end of the text.
fn found(st : State) -> Item {
  match st.peek() {
    Some(ch) => Item::Token(ch)
    None => Item::End
  }
}

///|
/// Repeats a parser until it fails, collecting the values.
///
/// Stops as soon as a round reads nothing, so a parser that can succeed on
/// empty text ends the repetition instead of running forever.
pub fn[T] Parser::many(self : Parser[T]) -> Parser[Array[T]] {
  Parser::new(fn(st) {
    let values = []
    let mut at = st
    while true {
      match self.apply(at) {
        Value(value, after) =>
          if after.at == at.at {
            break
          } else {
            values.push(value)
            at = after
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
    Value(values, at)
  })
}

///|
/// Repeats a parser until it fails, and requires at least one round.
pub fn[T] Parser::many1(self : Parser[T]) -> Parser[Array[T]] {
  self.and_then(first => {
    self
    .many()
    .map(rest => {
      let values = Array(capacity=rest.length() + 1)
      values.push(first)
      values.append(rest[:])
      values
    })
  })
}

///|
/// Runs a parser without keeping its values, as often as it matches.
pub fn[T] Parser::skip_many(self : Parser[T]) -> Parser[Unit] {
  self.many().map(_ => ())
}

///|
/// Runs a parser without keeping its values, at least once.
pub fn[T] Parser::skip_many1(self : Parser[T]) -> Parser[Unit] {
  self.many1().map(_ => ())
}

///|
/// Runs a parser a fixed number of times.
pub fn[T] Parser::count(self : Parser[T], times : Int32) -> Parser[Array[T]] {
  Parser::new(fn(st) {
    let values = Array(capacity=times)
    let mut at = st
    for _ in 0..<times {
      match self.apply(at) {
        Value(value, after) => {
          values.push(value)
          at = after
        }
        Problem(error, consumed) => return Problem(error, consumed)
        Starved(need) => return Starved(need)
      }
    }
    Value(values, at)
  })
}

///|
/// Runs a parser as often as it matches, with `separator` between the values,
/// and keeps the values. Zero matches are allowed.
pub fn[T, S] Parser::sep_by(
  self : Parser[T],
  separator : Parser[S],
) -> Parser[Array[T]] {
  self.sep_by1(separator).or(pure([]))
}

///|
/// Like [`Parser::sep_by`], but requires at least one value.
pub fn[T, S] Parser::sep_by1(
  self : Parser[T],
  separator : Parser[S],
) -> Parser[Array[T]] {
  self.and_then(first => {
    separator
    .then(self)
    .many()
    .map(rest => {
      let values = Array(capacity=rest.length() + 1)
      values.push(first)
      values.append(rest[:])
      values
    })
  })
}

///|
/// Runs a parser as often as it matches, with `separator` after each value,
/// and keeps the values. Zero matches are allowed.
pub fn[T, S] Parser::sep_end_by(
  self : Parser[T],
  separator : Parser[S],
) -> Parser[Array[T]] {
  self.sep_end_by1(separator).or(pure([]))
}

///|
/// Like [`Parser::sep_end_by`], but requires at least one value.
pub fn[T, S] Parser::sep_end_by1(
  self : Parser[T],
  separator : Parser[S],
) -> Parser[Array[T]] {
  self.skip(separator).many1()
}

///|
/// Runs a parser between an opening and a closing parser, keeping its value.
pub fn[T, O, C] between(
  open : Parser[O],
  close : Parser[C],
  inner : Parser[T],
) -> Parser[T] {
  open.then(inner).skip(close)
}

///|
/// Runs a parser if it matches and produces nothing otherwise.
///
/// The difference from [`Parser::or`] with `pure(None)` is that a parser that
/// has already read something cannot be skipped: the failure still stands.
pub fn[T] Parser::optional(self : Parser[T]) -> Parser[T?] {
  Parser::new(st => {
    match self.apply(st) {
      Value(value, after) => Value(Some(value), after)
      Problem(error, consumed) =>
        if consumed {
          Problem(error, true)
        } else {
          Value(None, st)
        }
      Starved(need) => Starved(need)
    }
  })
}

///|
/// Runs a parser if it matches and produces `fallback` otherwise.
pub fn[T] Parser::or_else(self : Parser[T], fallback : T) -> Parser[T] {
  self
  .optional()
  .map(found => {
    match found {
      Some(value) => value
      None => fallback
    }
  })
}

///|
/// Folds a run of values separated by a left-associative operator.
///
/// `chain_left(number, plus)` reads `1+2+3` as `(1+2)+3`, which is what the
/// operator table ends up using for every left-associative operator.
pub fn[T] Parser::chain_left(
  self : Parser[T],
  operator : Parser[(T, T) -> T],
) -> Parser[T] {
  Parser::new(fn(st) {
    match self.apply(st) {
      Value(first, after) => {
        let mut value = first
        let mut at = after
        while true {
          match operator.apply(at) {
            Value(combine, after_op) =>
              match self.apply(after_op) {
                Value(right, after_right) => {
                  value = combine(value, right)
                  at = after_right
                }
                Problem(error, consumed) =>
                  return Problem(error, consumed || after_op.at > st.at)
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
      }
      Problem(error, consumed) => Problem(error, consumed)
      Starved(need) => Starved(need)
    }
  })
}

///|
/// Folds a run of values separated by a right-associative operator, reading
/// `2^3^2` as `2^(3^2)`.
pub fn[T] Parser::chain_right(
  self : Parser[T],
  operator : Parser[(T, T) -> T],
) -> Parser[T] {
  self.and_then(left => {
    let rest = operator.and_then(combine => {
      self.chain_right(operator).map(right => (combine, right))
    })
    rest
    .optional()
    .map(tail => {
      match tail {
        Some((combine, right)) => combine(left, right)
        None => left
      }
    })
  })
}

///|
/// Repeats a parser until `stop` matches, keeping what the parser produced and
/// discarding the stop.
pub fn[T, S] Parser::many_till(
  self : Parser[T],
  stop : Parser[S],
) -> Parser[Array[T]] {
  Parser::new(fn(st) {
    let values = []
    let mut at = st
    while true {
      match stop.apply(at) {
        Value(_, after) => return Value(values, after)
        Problem(_, consumed) =>
          if consumed {
            return Problem(
              {
                position: at.position(),
                got: Some(found(at)),
                want: [],
                notes: [],
              },
              true,
            )
          }
        Starved(need) => return Starved(need)
      }
      match self.apply(at) {
        Value(value, after) =>
          if after.at == at.at {
            return Problem(
              {
                position: at.position(),
                got: Some(found(at)),
                want: [],
                notes: [],
              },
              true,
            )
          } else {
            values.push(value)
            at = after
          }
        Problem(error, consumed) =>
          return Problem(error, consumed || error.position.at > st.at)
        Starved(need) => return Starved(need)
      }
    }
    Value(values, at)
  })
}

///|
/// Tries the parsers in order and produces the first value that one of them
/// can parse.
pub fn[T] choice(parsers : Array[Parser[T]]) -> Parser[T] {
  Parser::new(fn(st) {
    let mut best : Refused? = None
    for parser in parsers {
      match parser.apply(st) {
        Value(value, after) => return Value(value, after)
        Starved(need) => return Starved(need)
        Problem(error, consumed) => {
          if consumed {
            return Problem(error, true)
          }
          best = match best {
            None => Some(error)
            Some(previous) => Some(previous.merge(error))
          }
        }
      }
    }
    match best {
      None =>
        Problem(
          { position: st.position(), got: None, want: [], notes: [], },
          false,
        )
      Some(error) => Problem(error, false)
    }
  })
}

///|
/// Tries a second parser when the first one fails without having read
/// anything.
///
/// This is the choice that makes a grammar out of alternatives. The refusals
/// of both branches are merged, so a reader sees every alternative that was
/// available at the place where the text stopped making sense.
pub fn[T] Parser::or(self : Parser[T], other : Parser[T]) -> Parser[T] {
  Parser::new(st => {
    match self.apply(st) {
      Value(value, after) => Value(value, after)
      Starved(need) => Starved(need)
      Problem(error, consumed) =>
        if consumed {
          Problem(error, true)
        } else {
          match other.apply(st) {
            Value(value, after) => Value(value, after)
            Starved(need) => Starved(need)
            Problem(other_error, other_consumed) =>
              Problem(error.merge(other_error), other_consumed)
          }
        }
    }
  })
}

///|
/// Reads the next character without any expectation attached, so that a
/// failure of it says only what was found.
pub let any_char : Parser[Char] = Parser::new(fn(st) {
  match st.peek() {
    Some(ch) => Value(ch, st.step())
    None =>
      match st.ending([]) {
        Ended(error) => Problem(error, false)
        Waiting(need) => Starved(need)
      }
  }
})

///|
/// Reads the next character if it passes `check`.
///
/// `want` names what the caller was looking for; without it a refusal says
/// only what it found, which is the right thing for a predicate the reader
/// could not have guessed.
pub fn satisfy(check : (Char) -> Bool, want? : Item) -> Parser[Char] {
  let wanted = match want {
    Some(item) => [item]
    None => []
  }
  Parser::new(fn(st) {
    match st.peek() {
      Some(ch) =>
        if check(ch) {
          Value(ch, st.step())
        } else {
          Problem(
            {
              position: st.position(),
              got: Some(Item::Token(ch)),
              want: wanted,
              notes: [],
            },
            false,
          )
        }
      None =>
        match st.ending(wanted) {
          Ended(error) => Problem(error, false)
          Waiting(need) => Starved(need)
        }
    }
  })
}

///|
/// Runs a parser, and when it refuses, runs `recover` at the place the refusal
/// points at, keeping whatever it produces.
///
/// The refusal is kept with the value, so a caller that wants to report
/// several problems can collect them and still walk the rest of the document:
/// ```mbt check
/// test {
///   let item = @moonpsec.satisfy(ch => ch == '1').label("a digit")
///   let forgiving = item.recover_with(_ => @moonpsec.pure('0'))
///   let repaired = @moonpsec.run(forgiving, "")
///   assert_eq(repaired.unwrap().value, '0')
/// }
/// ```
pub fn[T] Parser::recover_with(
  self : Parser[T],
  recover : (Refused) -> Parser[T],
) -> Parser[Repair[T]] {
  Parser::new(fn(st) {
    match self.apply(st) {
      Value(value, after) => Value({ value, refusal: None, }, after)
      Starved(need) => Starved(need)
      Problem(error, consumed) => {
        let at = st.from_position(error.position)
        match recover(error).apply(at) {
          Value(value, after) => Value({ value, refusal: Some(error), }, after)
          Starved(need) => Starved(need)
          Problem(_, _) => Problem(error, consumed)
        }
      }
    }
  })
}

///|
/// A value a recovered parser produced, together with the refusal it got past.
///
/// `refusal` is nothing when the parser matched as written. Keeping it next to
/// the value is what lets a caller report every problem of a document instead
/// of stopping at the first one.
#derive(Debug)
pub(all) struct Repair[T] {
  ///
  value : T
  ///
  refusal : Refused?
}

///|
/// Runs a parser over the whole of `text` and returns its value.
///
/// Text left over is a refusal, the same as any other: a grammar that
/// describes one value describes the whole of a document, so `run` adds the
/// end of the text to it.
///
/// ```mbt check
/// test {
///   let digits = @moonpsec.satisfy(ch => ch >= '0' && ch <= '9').many()
///   assert_eq(@moonpsec.run(digits, "123").unwrap().length(), 3)
/// }
/// ```
pub fn[T] run(
  parser : Parser[T],
  text : StringView,
  tab~ : Int32 = 8,
) -> Result[T, Refused] {
  match parse(parser, text, tab~) {
    Ok((value, _)) => Ok(value)
    Err(error) => Err(error)
  }
}

///|
/// Runs a parser over the whole of `text` and returns its value with the
/// position it ended at, which is what a test of a line or a column wants.
///
/// ```mbt check
/// test {
///   let word = @moonpsec.satisfy(ch => ch != ' ').many()
///   let (value, end) = @moonpsec.parse(word, "hi").unwrap()
///   assert_eq(value.length(), 2)
///   assert_eq(end.line, 1)
///   assert_eq(end.column, 3)
/// }
/// ```
pub fn[T] parse(
  parser : Parser[T],
  text : StringView,
  tab~ : Int32 = 8,
) -> Result[(T, Position), Refused] {
  match run_at(parser, State::start(text, complete=true, tab~)) {
    Err(error) => Err(error)
    Ok((value, after)) =>
      match after.peek() {
        None => Ok((value, after.position()))
        Some(ch) =>
          Err({
            position: after.position(),
            got: Some(Item::Token(ch)),
            want: [Item::End],
            notes: [],
          })
      }
  }
}

///|
/// Runs a parser over `text` and returns its value with the text it did not
/// read.
pub fn[T] run_partial(
  parser : Parser[T],
  text : StringView,
  tab~ : Int32 = 8,
) -> Result[(T, StringView), Refused] {
  match run_at(parser, State::start(text, complete=true, tab~)) {
    Err(error) => Err(error)
    Ok((value, after)) => Ok((value, after.remaining()))
  }
}

///|
/// Runs a parser over `text` and returns its value with the position it
/// stopped at, whether or not it read everything.
///
/// ```mbt check
/// test {
///   let (_, place) = @moonpsec.run_position(@moonpsec.take(1), "\ta").unwrap()
///   assert_eq(place.column, 9)
/// }
/// ```
pub fn[T] run_position(
  parser : Parser[T],
  text : StringView,
  tab~ : Int32 = 8,
) -> Result[(T, Position), Refused] {
  match run_at(parser, State::start(text, complete=true, tab~)) {
    Err(error) => Err(error)
    Ok((value, after)) => Ok((value, after.position()))
  }
}

///|
fn[T] run_at(parser : Parser[T], start : State) -> Result[(T, State), Refused] {
  match parser.apply(start) {
    Value(value, after) => Ok((value, after))
    Problem(error, _) => Err(error)
    Starved(_) =>
      Err({
        position: start.position(),
        got: None,
        want: [],
        notes: ["the parser wanted more text than was given"],
      })
  }
}
