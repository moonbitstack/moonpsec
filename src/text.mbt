// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads exactly `text` and produces it.
///
/// The whole run is compared, and a mismatch is reported against the whole run
/// rather than the character that broke it, because that is what the grammar
/// was asking for.
///
/// ```mbt check
/// test {
///   assert_eq(@moonpsec.run(@moonpsec.string("let"), "let"), Ok("let"))
/// }
/// ```
pub fn string(text : StringView) -> Parser[String] {
  let want = [Item::Tokens(text.to_owned())]
  Parser::new(fn(st) {
    let mut at = st
    let mut read = 0
    for expected in text {
      match at.peek() {
        None =>
          match at.ending(want) {
            Ended(error) => return Problem(error, read > 0)
            Waiting(need) => return Starved(need)
          }
        Some(ch) =>
          if ch == expected {
            at = at.step()
            read += 1
          } else {
            return Problem(
              {
                position: at.position(),
                got: Some(Item::Token(ch)),
                want,
                notes: [],
              },
              read > 0,
            )
          }
      }
    }
    Value(text.to_owned(), at)
  })
}

///|
/// Reads `text` in either ASCII case and produces what the grammar wrote,
/// which keeps `TRUE` from becoming `true` in the result.
pub fn string_ci(text : StringView) -> Parser[String] {
  let want = [Item::Tokens(text.to_owned())]
  Parser::new(fn(st) {
    let mut at = st
    let mut read = 0
    for expected in text {
      match at.peek() {
        None =>
          match at.ending(want) {
            Ended(error) => return Problem(error, read > 0)
            Waiting(need) => return Starved(need)
          }
        Some(ch) =>
          if ch.to_ascii_lowercase() == expected.to_ascii_lowercase() {
            at = at.step()
            read += 1
          } else {
            return Problem(
              {
                position: at.position(),
                got: Some(Item::Token(ch)),
                want,
                notes: [],
              },
              read > 0,
            )
          }
      }
    }
    Value(text.to_owned(), at)
  })
}

///|
/// Reads characters while `check` holds and produces them as text. Reads
/// nothing when the first character does not pass.
///
/// ```mbt check
/// test {
///   let spaces = @moonpsec.take_while(ch => ch == ' ')
///   assert_eq(@moonpsec.run(spaces, "   "), Ok("   "))
/// }
/// ```
pub fn take_while(check : (Char) -> Bool) -> Parser[String] {
  Parser::new(fn(st) {
    let mut at = st
    while true {
      match at.peek() {
        Some(ch) => if check(ch) { at = at.step() } else { break }
        None => {
          // The run may continue in text that has not arrived yet, so a scan
          // that stops at a chunk boundary waits instead of guessing.
          if !at.complete {
            return Starved(1)
          }
          break
        }
      }
    }
    Value(st.text.exact_view(start=st.at, end=at.at).to_owned(), at)
  })
}

///|
/// Like [`take_while`], but requires at least one character.
pub fn take_while1(check : (Char) -> Bool) -> Parser[String] {
  Parser::new(fn(st) {
    let mut at = st
    while true {
      match at.peek() {
        Some(ch) => if check(ch) { at = at.step() } else { break }
        None => {
          if !at.complete {
            return Starved(1)
          }
          break
        }
      }
    }
    if at.at == st.at {
      return Problem(
        { position: st.position(), got: Some(found(st)), want: [], notes: [], },
        false,
      )
    }
    Value(st.text.exact_view(start=st.at, end=at.at).to_owned(), at)
  })
}

///|
/// Reads everything that is left.
///
/// Over a text that is still arriving this waits for the end rather than
/// handing back half of it.
pub let take_rest : Parser[String] = Parser::new(fn(st) {
  if !st.complete {
    return Starved(1)
  }
  let mut at = st
  while at.peek() is Some(_) {
    at = at.step()
  }
  Value(st.remaining().to_owned(), at)
})

///|
/// Succeeds only at the end of the text, and reads nothing.
///
/// ```mbt check
/// test {
///   assert_eq(@moonpsec.run(@moonpsec.eof, ""), Ok(()))
/// }
/// ```
pub let eof : Parser[Unit] = Parser::new(fn(st) {
  match st.peek() {
    None => if st.complete { Value((), st) } else { Starved(1) }
    Some(ch) =>
      Problem(
        {
          position: st.position(),
          got: Some(Item::Token(ch)),
          want: [Item::End],
          notes: [],
        },
        false,
      )
  }
})

///|
/// Whether the text has ended, without requiring it: an `if` in a grammar
/// wants to ask rather than to insist.
pub let at_end : Parser[Bool] = Parser::new(fn(st) {
  match st.peek() {
    None => if st.complete { Value(true, st) } else { Starved(1) }
    Some(_) => Value(false, st)
  }
})

///|
/// Reads exactly `times` characters and produces them, refusing when the text
/// ends first.
pub fn take(times : Int32) -> Parser[String] {
  Parser::new(fn(st) {
    let mut at = st
    for _ in 0..<times {
      match at.peek() {
        Some(_) => at = at.step()
        None =>
          match at.ending([]) {
            Ended(error) => return Problem(error, at.at > st.at)
            Waiting(need) => return Starved(need)
          }
      }
    }
    Value(st.text.exact_view(start=st.at, end=at.at).to_owned(), at)
  })
}
