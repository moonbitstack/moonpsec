// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where a running parser stands: the text, how far into it the parser has
/// read, the line and column that offset is on, and whether the text is known
/// to be complete.
///
/// A parser is a function from one of these to a reply, so every combinator
/// gets the rest of the text by way of the state it is handed and gives back
/// the state it leaves behind. Nothing is ever mutated, which is what makes
/// backtracking a matter of holding on to an older state.
pub struct State {
  text : StringView
  at : Int32
  line : Int32
  column : Int32
  complete : Bool
  tab : Int32
}

///|
fn State::start(text : StringView, complete~ : Bool, tab~ : Int32) -> State {
  { text, at: 0, line: 1, column: 1, complete, tab, }
}

///|
fn State::position(self : State) -> Position {
  { at: self.at, line: self.line, column: self.column, }
}

///|
fn State::from_position(self : State, position : Position) -> State {
  { ..self, at: position.at, line: position.line, column: position.column, }
}

///|
fn State::remaining(self : State) -> StringView {
  self.text.exact_view(start=self.at, end=self.text.length())
}

///|
/// The character at `offset` of `text`, or nothing at the end of it.
///
/// A [`StringView`] indexes UTF-16 code units, so a character above the basic
/// plane arrives as two of them and has to be put back together; leaving it
/// split would give a parser two half-characters where the text has one.
fn char_at(text : StringView, offset : Int32) -> Char? {
  let length = text.length()
  if offset >= length || offset < 0 {
    return None
  }
  let unit = text.unsafe_get(offset)
  if unit.is_leading_surrogate() && offset + 1 < length {
    let next = text.unsafe_get(offset + 1)
    if next.is_trailing_surrogate() {
      let code = 0x10000 +
        ((unit.to_int() - 0xD800) << 10) +
        (next.to_int() - 0xDC00)
      return Some(code.unsafe_to_char())
    }
  }
  Some(unit.unsafe_to_char())
}

///|
/// How many code units the character at `offset` occupies.
fn char_width(text : StringView, offset : Int32) -> Int32 {
  guard offset >= 0 && offset < text.length() else { 0 }
  if text.unsafe_get(offset).is_leading_surrogate() &&
    offset + 1 < text.length() &&
    text.unsafe_get(offset + 1).is_trailing_surrogate() {
    2
  } else {
    1
  }
}

///|
fn State::peek(self : State) -> Char? {
  char_at(self.text, self.at)
}

///|
fn State::width(self : State) -> Int32 {
  char_width(self.text, self.at)
}

///|
/// Advances over one character. The caller has already looked at it, so this
/// only has to move the counters.
fn State::step(self : State) -> State {
  match self.peek() {
    None => self
    Some(ch) => {
      let width = self.width()
      let here : Position = {
        at: self.at,
        line: self.line,
        column: self.column,
      }
      let moved = here.advance(ch, self.tab)
      { ..self, at: self.at + width, line: moved.line, column: moved.column, }
    }
  }
}

///|
/// The refusal a parser produces when it wanted something and the text had
/// run out, in the two cases there are: the text is over, so this is a
/// refusal, or more may come, so the parser asks to be run again later.
priv enum Ending {
  Ended(Refused)
  Waiting(Int32)
}

///|
fn State::ending(self : State, want : Array[Item]) -> Ending {
  if self.complete {
    Ended({ position: self.position(), got: Some(End), want, notes: [], })
  } else {
    Waiting(1)
  }
}

///|
/// Where `offset` falls in `text`, counting from one.
///
/// A refusal made at the end of a run has only an offset; this turns it back
/// into the line and column a reader needs, once, rather than keeping a
/// position for every character of a document.
fn position_at(text : StringView, offset : Int32, tab : Int32) -> Position {
  let mut at = 0
  let mut line = 1
  let mut column = 1
  while at < offset {
    match char_at(text, at) {
      None => break
      Some(ch) => {
        let width = char_width(text, at)
        let moved = ({ at, line, column, } : Position).advance(ch, tab)
        at += width
        line = moved.line
        column = moved.column
      }
    }
  }
  { at, line, column, }
}
