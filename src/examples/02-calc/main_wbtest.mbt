// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the precedence of the table decides what binds first" {
  assert_eq(@moonpsec.run(expression, "1 + 2 * 3").unwrap(), 7)
  assert_eq(@moonpsec.run(expression, "(1 + 2) * 3").unwrap(), 9)
  assert_eq(@moonpsec.run(expression, "2 ^ 3 ^ 2").unwrap(), 512)
  assert_eq(@moonpsec.run(expression, "8 - 2 - 3").unwrap(), 3)
  assert_eq(@moonpsec.run(expression, "-4 + 10").unwrap(), 6)
  assert_eq(@moonpsec.run(expression, "4! + 1").unwrap(), 25)
}

///|
test "an expression inside parentheses goes back to the whole grammar" {
  assert_eq(@moonpsec.run(expression, "2 * (3 + (4 - 1))").unwrap(), 12)
}

///|
test "an expression that stops in the middle says what it wanted" {
  let refusal = @moonpsec.run(expression, "1 + 2 *").unwrap_err()
  assert_eq(refusal.position.column, 8)
  assert_eq(refusal.got, Some(@moonpsec.Item::End))
}
