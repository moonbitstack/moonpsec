// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the corpus" {
  let summary = @suite.run()
  println(summary.to_string())
  assert_eq(summary.cases, 318)
  assert_eq(summary.wrong.length(), 0)
  // The one case the two readers answer differently, on purpose: a document
  // nested five hundred levels deep is past this reader's limit and within the
  // other one's. RFC 8259 leaves the limit to the reader, so both answers are
  // allowed; the list is exact so that a new divergence fails the test.
  assert_eq(summary.disputed, ["i_structure_500_nested_arrays"])
  assert_eq(summary.unequal.length(), 0)
}
