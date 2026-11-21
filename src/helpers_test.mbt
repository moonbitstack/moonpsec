// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Whether the parser refused, for the tests that care about the verdict and
/// not about what was said.
fn[T] refused(result : Result[T, @moonpsec.Refused]) -> Bool {
  match result {
    Ok(_) => false
    Err(_) => true
  }
}
