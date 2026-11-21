// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads a few documents and prints what came back, then reads a document that
/// is wrong and prints the refusal it earned.
///
///     moon run src/examples/01-json
#coverage.skip
fn main {
  let documents = [
    "null", "{\"name\": \"moonpsec\", \"size\": 12, \"tags\": [\"parser\", \"moonbit\"]}",
    "[1, 2.5e3, true, false, \"\\u4e2d\\u6587\"]",
  ]
  for document in documents {
    println(@json.parse(document).unwrap().to_string())
  }
  let broken = "{\"name\": \"moonpsec\", \"tags\": [1, 2,]}"
  let refusal = @json.parse(broken).unwrap_err()
  println(refusal.to_string())
  println(refusal.pretty(broken))
}
