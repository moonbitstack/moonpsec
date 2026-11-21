// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A place in the text being parsed.
///
/// `at` is the offset that a [`StringView`] indexes by, in UTF-16 code units
/// from the start of the text handed to the parser. `line` and `column` start
/// at one, because that is how an editor counts and a position a reader cannot
/// find in their file is half a position.
#derive(Eq, Debug)
pub(all) struct Position {
  ///
  at : Int32
  ///
  line : Int32
  ///
  column : Int32
}

///|
/// The position at the start of any text: offset zero, line one, column one.
pub let start : Position = { at: 0, line: 1, column: 1, }

///|
/// Whether `self` stands before `other` in the text.
///
/// The offset decides; it is the only one of the three that has to move
/// forward, and comparing on it keeps two positions taken at the same place
/// comparable even when one of them came from a recovered error.
pub fn Position::before(self : Position, other : Position) -> Bool {
  self.at < other.at
}

///|
/// Renders the position the way editors and compilers do: `line:column`.
pub fn Position::to_string(self : Position) -> String {
  "\{self.line}:\{self.column}"
}

///|
/// Moves one character forward, counting a tab as a jump to the next tab stop.
///
/// Tab stops are counted the way every terminal and editor counts them: the
/// column after a tab is the next multiple of `tab` plus one, so with the
/// default width of eight, a tab at column 3 lands on column 9.
///
/// The offset grows by the code units the character occupies — two above the
/// basic plane — so that it stays an offset into the text rather than a count
/// of characters.
fn Position::advance(self : Position, ch : Char, tab : Int32) -> Position {
  let at = self.at + (if ch.to_int() > 0xFFFF { 2 } else { 1 })
  if ch == '\n' {
    { at, line: self.line + 1, column: 1, }
  } else if ch == '\t' {
    let stops = if tab <= 0 { 1 } else { tab }
    {
      at,
      line: self.line,
      column: self.column + stops - (self.column - 1) % stops,
    }
  } else {
    { at, line: self.line, column: self.column + 1, }
  }
}
