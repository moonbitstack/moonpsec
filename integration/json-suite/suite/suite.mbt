// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What came of reading the corpus.
pub(all) struct Summary {
  ///
  /// Cases read.
  cases : Int32
  ///
  /// Cases this reader accepted.
  accepted : Int32
  ///
  /// Cases this reader refused.
  refused : Int32
  ///
  /// Cases the required verdict was not reached on.
  wrong : Array[String]
  ///
  /// Cases where the family's JSON library reached the other verdict.
  disputed : Array[String]
  ///
  /// Cases both accepted but read differently.
  unequal : Array[String]
}

///|
/// Reads every case of the corpus and answers the three questions the suite is
/// for: does the reader reach the required verdict, does the other library
/// reach the same one, and does the value it read match.
///
/// A case is bytes. Text that is not UTF-8 cannot reach a reader of text at
/// all, so it is refused here, which is what the suite asks for the files that
/// are not text and what the other library does when it decodes.
pub fn run() -> Summary {
  let wrong = []
  let disputed = []
  let unequal = []
  let mut accepted = 0
  let mut refused = 0
  for entry in cases() {
    let (name, text, must_accept) = entry
    let bytes = @hex.decode(text) catch { _ => b"" }
    let decoded = Some(@utf8.decode(bytes)) catch { _ => None }
    let ours = match decoded {
      None => None
      Some(document) => @json.parse(document).to_option()
    }
    let theirs = Some(@moonjson.load(bytes, @moonjson.strict)) catch {
      _ => None
    }
    if ours is Some(_) {
      accepted += 1
    } else {
      refused += 1
    }
    if (ours is Some(_)) != must_accept {
      wrong.push(name)
    }
    if (ours is Some(_)) != (theirs is Some(_)) {
      disputed.push(name)
    }
    match (ours, theirs) {
      (Some(mine), Some(other)) => if !same(mine, other) { unequal.push(name) }
      _ => ()
    }
  }
  { cases: accepted + refused, accepted, refused, wrong, disputed, unequal, }
}

///|
/// Whether two readings of the same document are the same document.
fn same(mine : @json.Value, other : @corejson.Json) -> Bool {
  match (mine, other) {
    (Null, Null) | (True, True) | (False, False) => true
    (Number(digits), Number(value, repr~)) => {
      let same_text = match repr {
        Some(text) => text == digits
        None => false
      }
      let same_value = try @string.parse_double(digits) == value catch {
        _ => false
      }
      same_text || same_value
    }
    (Text(text), String(theirs)) => text == theirs
    (Array(items), Array(others)) =>
      items.length() == others.length() &&
      ({
        let mut equal = true
        for index, item in items {
          if !same(item, others[index]) {
            equal = false
          }
        }
        equal
      })
    (Object(members), Object(others)) =>
      members.length() == others.length() &&
      ({
        let mut equal = true
        for pair in members {
          match others.get(pair.0) {
            Some(value) => if !same(pair.1, value) { equal = false }
            None => equal = false
          }
        }
        equal
      })
    _ => false
  }
}

///|
/// The summary in one line, which is what a log and a delivery note quote.
pub fn Summary::to_string(self : Summary) -> String {
  let text = StringBuilder()
  text.write_string(
    "json suite: \{self.cases} cases, \{self.accepted} accepted, \{self.refused} refused",
  )
  text.write_string(
    ", \{self.wrong.length()} wrong, \{self.disputed.length()} disputed",
  )
  text.write_string(", \{self.unequal.length()} unequal")
  for name in self.wrong {
    text.write_string("\n  wrong: \{name}")
  }
  for name in self.disputed {
    text.write_string("\n  disputed: \{name}")
  }
  for name in self.unequal {
    text.write_string("\n  unequal: \{name}")
  }
  text.to_string()
}
