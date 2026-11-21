// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One thing an error talks about: what was found, or what was wanted.
///
/// A single character and a run of them are different variants because a
/// reader expects `'a'` for one and `"abc"` for several, and because the
/// expected sets of two branches are merged as sets of these.
#derive(Eq, Debug)
pub(all) enum Item {
  ///
  /// A single character.
  Token(Char)
  ///
  /// A run of characters, whether one long or several.
  Tokens(String)
  ///
  /// A name a parser was given with [`label`](Parser::label) — "integer",
  /// "operator" — instead of the characters that would have matched.
  Label(String)
  ///
  /// The end of the text.
  End
}

///|
/// Renders a character the way error messages spell it out: a printable
/// character in single quotes, a control character by name, and a space as
/// `space`, because `' '` is invisible in a message.
pub fn Item::to_string(self : Item) -> String {
  match self {
    Token(ch) => char_pretty(ch)
    Tokens(text) => tokens_pretty(text)
    Label(name) => name
    End => "end of input"
  }
}

///|
fn char_pretty(ch : Char) -> String {
  if ch == ' ' {
    "space"
  } else {
    match control_name(ch) {
      Some(name) => name
      None => "'\{ch}'"
    }
  }
}

///|
/// A run of characters is quoted, and any control character inside it keeps
/// the name it has on its own, in angle brackets, so that a message stays on
/// one line and still says which character it means.
fn tokens_pretty(text : String) -> String {
  if text.length() == 1 && char_at(text[:], 0) is Some(ch) {
    return char_pretty(ch)
  }
  if text == "\r\n" {
    return "crlf newline"
  }
  let out = StringBuilder()
  out.write_char('"')
  for ch in text {
    match control_name(ch) {
      Some(name) => {
        out.write_char('<')
        out.write_string(name)
        out.write_char('>')
      }
      None => out.write_char(ch)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn control_name(ch : Char) -> String? {
  match ch.to_int() {
    0 => Some("null")
    1 => Some("start of heading")
    2 => Some("start of text")
    3 => Some("end of text")
    4 => Some("end of transmission")
    5 => Some("enquiry")
    6 => Some("acknowledge")
    7 => Some("bell")
    8 => Some("backspace")
    9 => Some("tab")
    10 => Some("newline")
    11 => Some("vertical tab")
    12 => Some("form feed")
    13 => Some("carriage return")
    14 => Some("shift out")
    15 => Some("shift in")
    16 => Some("data link escape")
    17 => Some("device control one")
    18 => Some("device control two")
    19 => Some("device control three")
    20 => Some("device control four")
    21 => Some("negative acknowledge")
    22 => Some("synchronous idle")
    23 => Some("end of transmission block")
    24 => Some("cancel")
    25 => Some("end of medium")
    26 => Some("substitute")
    27 => Some("escape")
    28 => Some("file separator")
    29 => Some("group separator")
    30 => Some("record separator")
    31 => Some("unit separator")
    127 => Some("delete")
    160 => Some("non-breaking space")
    _ => None
  }
}

///|
/// Why a parser refused the text, and where.
///
/// `got` is what the parser was looking at when it gave up, `want` is
/// everything that would have been accepted there, and `notes` holds the
/// free-form messages [`fail`](Parser::fail) was given. An error with all
/// three empty says only that something was refused, which is what a parser
/// with nothing to say produces.
#derive(Eq, Debug)
pub(all) struct Refused {
  ///
  /// Where the parser gave up.
  position : Position
  ///
  /// What was there, when the parser could name it.
  got : Item?
  ///
  /// What would have been accepted there, in the order it was collected.
  want : Array[Item]
  ///
  /// Messages attached to the refusal.
  notes : Array[String]
}

///|
/// Combines the refusals of two branches of a choice.
///
/// The branch that got further is the one whose complaint is worth keeping: it
/// saw more of the text, so what it expected is what the text was missing. When
/// both stopped at the same place the two sets of expectations are both right,
/// and a reader wants to see all of them at once.
pub fn Refused::merge(self : Refused, other : Refused) -> Refused {
  if self.position.at > other.position.at {
    return self
  }
  if other.position.at > self.position.at {
    return other
  }
  let got = match (self.got, other.got) {
    (None, None) => None
    (Some(item), None) => Some(item)
    (None, Some(item)) => Some(item)
    (Some(left), Some(right)) =>
      Some(if rank(left) >= rank(right) { left } else { right })
  }
  {
    position: self.position,
    got,
    want: union(self.want, other.want),
    notes: union(self.notes, other.notes),
  }
}

///|
/// How much an item says about the input, for picking between two of them at
/// the same place. A named label says less than the characters behind it, and
/// the end of the text says exactly where the reader is, so the more definite
/// item wins.
fn rank(item : Item) -> Int32 {
  match item {
    Tokens(_) => 0
    Token(_) => 1
    Label(_) => 2
    End => 3
  }
}

///|
/// Appends what is new in `more` to `base`, keeping the first occurrence of
/// anything that appears in both so the order stays the order of discovery.
fn[E : Eq] union(base : Array[E], more : Array[E]) -> Array[E] {
  let out = Array(capacity=base.length() + more.length())
  for item in base {
    out.push(item)
  }
  for item in more {
    if !out.contains(item) {
      out.push(item)
    }
  }
  out
}

///|
/// Says what would have been accepted, in the shape every compiler error
/// uses: sorted, without repeats, and joined the way English joins a list.
fn want_text(want : Array[Item]) -> String {
  let named = Array(capacity=want.length())
  for item in want {
    let text = item.to_string()
    if !named.contains(text) {
      named.push(text)
    }
  }
  named.sort()
  match named.length() {
    0 => ""
    1 => named[0]
    2 => "\{named[0]} or \{named[1]}"
    _ => {
      let head = named[:named.length() - 1].join(", ")
      "\{head}, or \{named[named.length() - 1]}"
    }
  }
}

///|
/// The refusal as plain lines, the way a compiler prints one: what was found,
/// then what was wanted, then any message the parser attached.
pub fn Refused::message(self : Refused) -> String {
  let lines = []
  if self.got is Some(item) {
    lines.push("unexpected \{item.to_string()}")
  }
  if self.want.length() > 0 {
    lines.push("expecting \{want_text(self.want)}")
  }
  for note in self.notes {
    lines.push(note)
  }
  if lines.is_empty() {
    return "unknown parse error"
  }
  lines.join("\n")
}

///|
/// The refusal in one line, prefixed with where it happened: what a log line
/// or a test assertion wants.
pub fn Refused::to_string(self : Refused) -> String {
  "\{self.position.to_string()}: \{self.message().replace_all(old="\n", new="; ")}"
}

///|
/// The refusal with the line it happened on and a caret under the character,
/// which is what a person needs to find it.
///
/// `text` is the whole text that was parsed. Lines are shown up to 120
/// characters around the position; tabs are expanded to eight-column stops so
/// the caret lands under the right character. Characters wider than one column
/// — CJK ideographs, most emoji — are counted as two.
pub fn Refused::pretty(
  self : Refused,
  text : StringView,
  tab~ : Int32 = 8,
) -> String {
  let out = StringBuilder()
  out.write_string(self.position.to_string())
  out.write_string(":\n")
  match locate(text, self.position, tab) {
    Some(line) => {
      let number = self.position.line.to_string()
      let pad = " ".repeat(number.length() + 1)
      out.write_string("\{pad}|\n")
      out.write_string("\{number} | \{line.text}\n")
      out.write_string("\{pad}| ")
      out.write_string(" ".repeat(line.before))
      out.write_string("^".repeat(line.width))
      out.write_char('\n')
    }
    None => ()
  }
  out.write_string(self.message())
  out.to_string()
}

///|
/// The line `position` is on, cut down to the width a terminal shows, with the
/// column the caret belongs in and how many characters it should cover.
priv struct Line {
  text : String
  before : Int32
  width : Int32
}

///|
fn locate(text : StringView, position : Position, tab : Int32) -> Line? {
  let total = text.length()
  if position.at > total {
    return None
  }
  let mut begin = position.at
  while begin > 0 && text[begin - 1] != '\n' {
    begin -= 1
  }
  let mut end = position.at
  while end < total && text[end] != '\n' {
    end += 1
  }
  if end > begin && text[end - 1] == '\r' {
    end -= 1
  }
  let raw = text.exact_view(start=begin, end~)
  let out = StringBuilder()
  let mut before = 0
  let mut column = 0
  let mut index = 0
  for ch in raw {
    if ch == '\t' {
      let stops = if tab <= 0 { 1 } else { tab }
      let spaces = stops - column % stops
      out.write_string(" ".repeat(spaces))
      if index < position.at - begin {
        before += spaces
      }
      column += spaces
    } else {
      let width = display_width(ch)
      out.write_char(ch)
      if index < position.at - begin {
        before += width
      }
      column += width
    }
    index += 1
  }
  Some({ text: out.to_string(), before, width: 1, })
}

///|
/// How many columns a character takes on a terminal: none for a combining mark,
/// two for the wide scripts, one otherwise. This is East Asian Width's main
/// ranges, enough to keep the caret under a CJK character or an emoji.
fn display_width(ch : Char) -> Int32 {
  let code = ch.to_int()
  if code < 0x300 {
    return 1
  }
  if (code >= 0x300 && code <= 0x36F) ||
    (code >= 0x1AB0 && code <= 0x1AFF) ||
    (code >= 0x1DC0 && code <= 0x1DFF) ||
    (code >= 0x20D0 && code <= 0x20FF) ||
    (code >= 0xFE00 && code <= 0xFE0F) ||
    (code >= 0xFE20 && code <= 0xFE2F) ||
    (code >= 0xE0100 && code <= 0xE01EF) {
    return 0
  }
  if (code >= 0x1100 && code <= 0x115F) ||
    (code >= 0x2E80 && code <= 0x303E) ||
    (code >= 0x3041 && code <= 0x33FF) ||
    (code >= 0x3400 && code <= 0x4DBF) ||
    (code >= 0x4E00 && code <= 0x9FFF) ||
    (code >= 0xA000 && code <= 0xA4CF) ||
    (code >= 0xA960 && code <= 0xA97F) ||
    (code >= 0xAC00 && code <= 0xD7A3) ||
    (code >= 0xF900 && code <= 0xFAFF) ||
    (code >= 0xFE10 && code <= 0xFE19) ||
    (code >= 0xFE30 && code <= 0xFE6F) ||
    (code >= 0xFF00 && code <= 0xFF60) ||
    (code >= 0xFFE0 && code <= 0xFFE6) ||
    (code >= 0x1F300 && code <= 0x1F64F) ||
    (code >= 0x1F900 && code <= 0x1F9FF) ||
    (code >= 0x20000 && code <= 0x3FFFD) {
    return 2
  }
  1
}
