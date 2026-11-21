// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads one document with each reader, several times, and prints how long the
/// rounds took.
///
///     moon run bench --target native
///
/// Both readers are given the same text and neither is allowed to see the
/// other's tree, so the two lines can be compared directly.
#coverage.skip
fn main {
  let document = sample(400)
  let rounds = 20
  println("document: \{document.length()} characters, \{rounds} rounds")
  let (ours, our_failures) = time(rounds, fn() { ignore(@json.parse(document)) })
  let (theirs, their_failures) = time(rounds, fn() raise {
    ignore(@moonjson.loads(document, @moonjson.strict))
  })
  println(
    "moonpsec: \{ours / rounds.to_double()} us per read, \{our_failures} refused",
  )
  println(
    "moonjson: \{theirs / rounds.to_double()} us per read, \{their_failures} refused",
  )
  println("ratio: \{ours / theirs} times the time of moonjson")
  let (scan, _) = time(rounds, fn() {
    ignore(@moonpsec.run(@moonpsec.take_rest, document))
  })
  let (steps, _) = time(rounds, fn() {
    ignore(@moonpsec.run(@moonpsec.any_char.count(document.length()), document))
  })
  println("take_rest: \{scan / rounds.to_double()} us")
  println("any_char counted: \{steps / rounds.to_double()} us")
}

///|
/// A document of `houses` objects, each with a few members of every kind.
fn sample(houses : Int32) -> String {
  let text = StringBuilder()
  text.write_string("[")
  for index in 0..<houses {
    if index > 0 {
      text.write_string(",")
    }
    text.write_string("{\"id\": \{index}, \"name\": \"house \{index}\", ")
    text.write_string(
      "\"price\": \{index}.5, \"tags\": [\"a\", \"b\", \"c\"], ",
    )
    text.write_string("\"open\": true, \"note\": null, ")
    text.write_string("\"where\": {\"lat\": -12.5, \"lon\": 34.25}}")
  }
  text.write_string("]")
  text.to_string()
}

///|
/// The microseconds `rounds` rounds of `work` took, and how many of them were
/// refused, which has to be none.
fn time(rounds : Int32, work : () -> Unit raise Error) -> (Double, Int32) {
  let mut refused = 0
  let started = @clock.monotonic_clock_start()
  for _ in 0..<rounds {
    work() catch {
      _ => refused += 1
    }
  }
  (@clock.monotonic_clock_end(started), refused)
}
