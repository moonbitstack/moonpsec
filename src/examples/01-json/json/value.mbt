// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A JSON value.
///
/// A number keeps the digits it was written with rather than becoming a
/// floating-point value: a document describes a number exactly, and turning
/// `1e999` into an infinity or `0.1` into its nearest double loses what the
/// document said. A reader that wants arithmetic converts at the point of use.
#derive(Eq, Debug)
pub(all) enum Value {
  ///
  Null
  ///
  True
  ///
  False
  ///
  Number(String)
  ///
  Text(String)
  ///
  Array(Array[Value])
  ///
  /// Members in the order they were written. Names may repeat; RFC 8259 says
  /// they should not, and a reader that silently kept the last one would be
  /// guessing which of two documents it was given.
  Object(Array[(String, Value)])
}

///|
/// Writes the value back as compact JSON.
pub fn Value::to_string(self : Value) -> String {
  let out = StringBuilder()
  self.write(out)
  out.to_string()
}

///|
fn Value::write(self : Value, out : StringBuilder) -> Unit {
  match self {
    Null => out.write_string("null")
    True => out.write_string("true")
    False => out.write_string("false")
    Number(text) => out.write_string(text)
    Text(text) => write_text(out, text)
    Array(items) => {
      out.write_char('[')
      for index, item in items {
        if index > 0 {
          out.write_char(',')
        }
        item.write(out)
      }
      out.write_char(']')
    }
    Object(members) => {
      out.write_char('{')
      for index, pair in members {
        if index > 0 {
          out.write_char(',')
        }
        write_text(out, pair.0)
        out.write_char(':')
        pair.1.write(out)
      }
      out.write_char('}')
    }
  }
}

///|
fn write_text(out : StringBuilder, text : String) -> Unit {
  out.write_char('"')
  for ch in text {
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      '\u{8}' => out.write_string("\\b")
      '\u{c}' => out.write_string("\\f")
      _ =>
        if ch.to_int() < 0x20 {
          out.write_string("\\u")
          out.write_string(hex4(ch.to_int()))
        } else {
          out.write_char(ch)
        }
    }
  }
  out.write_char('"')
}

///|
/// Four lowercase hexadecimal digits, the way an escape writes a code point.
fn hex4(code : Int32) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for shift in [12, 8, 4, 0] {
    out.write_char(digits.unsafe_get((code >> shift) & 0xF).unsafe_to_char())
  }
  out.to_string()
}
