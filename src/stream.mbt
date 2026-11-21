// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a parser makes of the text fed so far.
///
/// `Needs` is the answer that makes a parser incremental: the text ends in the
/// middle of something, so no verdict is possible until more arrives. Feeding
/// the next chunk and running again continues from the same place, and a
/// grammar never has to know that its text arrived in pieces.
pub(all) enum Progress[T] {
  ///
  /// A value, with the text that was left over after it.
  Ready(T, StringView)
  ///
  /// At least this many more code units are needed before anything can be
  /// decided.
  Needs(Int32)
  ///
  /// A refusal that more text cannot repair.
  Failed(Refused)
}

///|
/// Feeds a parser its text a chunk at a time.
///
/// The whole text is kept, and a chunk makes the parser run again from the
/// start of it, so a document fed in `k` chunks costs `k` runs. Chunks of a
/// kilobyte or more make that cost negligible; feeding a whole file one
/// character at a time would not, and there is no reason to.
pub struct Feeder[T] {
  parser : Parser[T]
  text : Ref[String]
  ended : Ref[Bool]
  tab : Int32
}

///|
/// Starts a parser on text that has not arrived yet.
///
/// ```mbt check
/// test {
///   let feeder = @moonpsec.feeder(@moonpsec.string("ab").eof())
///   assert_eq(feeder.feed("a") is @moonpsec.Progress::Needs(_), true)
///   assert_eq(feeder.feed("b") is @moonpsec.Progress::Needs(_), true)
///   assert_eq(feeder.finish().unwrap(), "ab")
/// }
/// ```
pub fn[T] feeder(parser : Parser[T], tab~ : Int32 = 8) -> Feeder[T] {
  { parser, text: Ref(""), ended: Ref(false), tab, }
}

///|
/// Adds a chunk and runs the parser over everything fed so far.
///
/// A grammar that describes a prefix of the text reaches `Ready` as soon as it
/// has what it needs, and the rest of the chunk comes back with the value. A
/// grammar that describes the whole document — one that ends in `eof`, or the
/// parser given to [`run`](run) — reaches `Ready` only when the text does.
pub fn[T] Feeder::feed(self : Feeder[T], chunk : StringView) -> Progress[T] {
  if self.ended.val {
    abort("text was already finished; nothing can be fed to it")
  }
  self.text.val = self.text.val + chunk.to_owned()
  self.advance()
}

///|
/// Ends the text and returns what the parser made of it, refusing anything it
/// did not read.
pub fn[T] Feeder::finish(self : Feeder[T]) -> Result[T, Refused] {
  if self.ended.val {
    abort("text was already finished")
  }
  self.ended.val = true
  match self.advance() {
    Ready(value, rest) =>
      match char_at(rest, 0) {
        None => Ok(value)
        Some(ch) => Err(trailing(self.text.val[:], rest, ch, self.tab))
      }
    Failed(error) => Err(error)
    Needs(_) =>
      Err({
        position: start,
        got: None,
        want: [],
        notes: ["the parser wanted more text after the end"],
      })
  }
}

///|
/// The text fed so far, which is what a refusal is rendered against.
pub fn[T] Feeder::text(self : Feeder[T]) -> StringView {
  self.text.val[:]
}

///|
fn[T] Feeder::advance(self : Feeder[T]) -> Progress[T] {
  let text = self.text.val
  let state = State::start(text[:], complete=self.ended.val, tab=self.tab)
  match self.parser.apply(state) {
    Value(value, after) => Ready(value, after.remaining())
    Problem(error, _) => Failed(error)
    Starved(need) => Needs(need)
  }
}

///|
fn trailing(
  text : StringView,
  rest : StringView,
  ch : Char,
  tab : Int32,
) -> Refused {
  let at = text.length() - rest.length()
  {
    position: position_at(text, at, tab),
    got: Some(Item::Token(ch)),
    want: [Item::End],
    notes: [],
  }
}

///|
/// Runs a parser over text that arrives as chunks, and requires it to describe
/// all of it.
///
/// This is [`run`](run) for a stream: the chunks are fed in order and the text
/// ends after the last one.
///
/// ```mbt check
/// test {
///   let parser = @moonpsec.take_while1(ch => ch.is_ascii_alphabetic())
///   assert_eq(
///     @moonpsec.stream(parser, ["ab"[:], "cd"[:]].iter()).unwrap(),
///     "abcd",
///   )
/// }
/// ```
pub fn[T] stream(
  parser : Parser[T],
  chunks : Iter[StringView],
  tab~ : Int32 = 8,
) -> Result[T, Refused] {
  let feeder = feeder(parser, tab~)
  for chunk in chunks {
    match feeder.feed(chunk) {
      Failed(error) => return Err(error)
      Ready(_, _) => ()
      Needs(_) => ()
    }
  }
  feeder.finish()
}
