// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn refused(result : Result[@json.Value, @moonpsec.Refused]) -> Bool {
  match result {
    Ok(_) => false
    Err(_) => true
  }
}

///|
test "the three literals" {
  assert_eq(@json.parse("null").unwrap(), @json.Value::Null)
  assert_eq(@json.parse("true").unwrap(), @json.Value::True)
  assert_eq(@json.parse("false").unwrap(), @json.Value::False)
}

///|
test "numbers keep the digits they were written with" {
  for text in ["0", "-0", "12", "-12", "1.5", "1e3", "1E+3", "2.5e-3", "0.0001"] {
    assert_eq(@json.parse(text).unwrap(), @json.Value::Number(text))
  }
}

///|
test "a number the grammar does not admit is refused" {
  for text in ["01", "+1", ".5", "1.", "1e", "1e+", "-", "1..2", "0x10"] {
    assert_eq(refused(@json.parse(text)), true)
  }
}

///|
test "a string keeps its content" {
  assert_eq(@json.parse("\"hello\"").unwrap(), @json.Value::Text("hello"))
  assert_eq(@json.parse("\"\"").unwrap(), @json.Value::Text(""))
}

///|
test "every escape of the grammar is read" {
  let text = "\"\\\" \\\\ \\/ \\b \\f \\n \\r \\t\""
  assert_eq(
    @json.parse(text).unwrap(),
    @json.Value::Text("\" \\ / \u{8} \u{c} \n \r \t"),
  )
}

///|
test "an escaped code point is read" {
  assert_eq(
    @json.parse("\"\\u4e2d\\u6587\"").unwrap(),
    @json.Value::Text("中文"),
  )
}

///|
test "a surrogate pair is put back together" {
  assert_eq(
    @json.parse("\"\\ud83d\\ude00\"").unwrap(),
    @json.Value::Text("😀"),
  )
}

///|
test "half a surrogate pair is refused" {
  assert_eq(refused(@json.parse("\"\\ud83d\"")), true)
  assert_eq(refused(@json.parse("\"\\ude00\"")), true)
}

///|
test "a control character has to be escaped" {
  assert_eq(refused(@json.parse("\"a\u{1}b\"")), true)
}

///|
test "an array keeps its order and its values" {
  let value = @json.parse("[1, [2, [3]], null]").unwrap()
  assert_eq(
    value,
    @json.Value::Array([
      @json.Value::Number("1"),
      @json.Value::Array([
        @json.Value::Number("2"),
        @json.Value::Array([@json.Value::Number("3")]),
      ]),
      @json.Value::Null,
    ]),
  )
}

///|
test "an object keeps the order the members were written in" {
  let value = @json.parse("{\"b\": 1, \"a\": 2}").unwrap()
  assert_eq(
    value,
    @json.Value::Object([
      ("b", @json.Value::Number("1")),
      ("a", @json.Value::Number("2")),
    ]),
  )
}

///|
test "the last value written for a repeated member name is the one it has" {
  let value = @json.parse("{\"a\": 1, \"b\": 2, \"a\": 3}").unwrap()
  assert_eq(
    value,
    @json.Value::Object([
      ("a", @json.Value::Number("3")),
      ("b", @json.Value::Number("2")),
    ]),
  )
}

///|
test "whitespace of the four kinds may surround anything" {
  let text = " \t\r\n{ \"a\" : \t[ 1 , 2 ] \r\n} \n"
  assert_eq(
    @json.parse(text).unwrap(),
    @json.Value::Object([
      (
        "a",
        @json.Value::Array([@json.Value::Number("1"), @json.Value::Number("2")]),
      ),
    ]),
  )
}

///|
test "a document that does not follow the grammar is refused" {
  for
    text in [
      "", "[]]", "{\"a\":}", "[1,]", "{\"a\" 1}", "'a'", "[1 2]", "{\"a\":1,}", "nul",
    ] {
    assert_eq(refused(@json.parse(text)), true)
  }
}

///|
test "a refusal names the line and column" {
  let error = @json.parse("{\n  \"a\": 1,\n  \"b\":\n}").unwrap_err()
  assert_eq(error.position.line, 4)
  assert_eq(error.position.column, 1)
}

///|
test "a document nested past the limit is refused rather than taking the stack down" {
  let deep = StringBuilder()
  for _ in 0..<200 {
    deep.write_char('[')
  }
  let error = @json.parse(deep.to_string()).unwrap_err()
  assert_eq(error.notes, ["nesting is deeper than 128 levels"])
}

///|
test "a document nested within the limit is read" {
  let deep = StringBuilder()
  for _ in 0..<100 {
    deep.write_char('[')
  }
  deep.write_char('1')
  for _ in 0..<100 {
    deep.write_char(']')
  }
  assert_eq(refused(@json.parse(deep.to_string())), false)
}

///|
test "a written value reads back as itself" {
  let text = "{\"a\":[1,2.5,\"x\",true,null],\"b\":{}}"
  assert_eq(@json.parse(text).unwrap().to_string(), text)
}
