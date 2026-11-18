///| 省略音 omit3 / omit5(v1.6)

///|
fn omit_ast(input : String) -> String {
  let result = @chord_language.parse(input)
  let errors = result.errors.map(fn(e) { e.kind_name() }).join(",")
  result.score.to_json_value().stringify() + " errors=" + errors
}

///|
fn first_error(input : String) -> String {
  let result = @chord_language.parse(input)
  if result.errors.is_empty() {
    "none"
  } else {
    result.errors[0].kind_name()
  }
}

///|
fn played(input : String) -> String {
  @chord_language.parse_to_playback(input, "C")
}

///|
fn shown(input : String) -> String {
  @chord_language.parse_to_notes_html(input, "C")
}

///|
test "omit: with and without parentheses mean the same" {
  let pairs : Array[(String, String)] = [
    ("1omit3", "1(omit3)"),
    ("1omit5", "1(omit5)"),
    ("1add9omit3", "1add9(omit3)"),
    ("1M7omit3", "1M7(omit3)"),
    ("579omit5", "57(9,omit5)"),
    ("1omit3omit5", "1(omit3,omit5)"),
    // 同じものは 1 つにまとめる
    ("1omit3(omit3)", "1(omit3)"),
  ]
  for pair in pairs {
    let (bare, paren) = pair
    assert_eq(omit_ast(bare), omit_ast(paren))
    assert_true(omit_ast(bare).has_suffix(" errors="))
  }
}

///|
test "omit: display is always in parentheses" {
  for
    pair in [
      ("1omit3", ">C(omit3)<"),
      ("1add9omit3", ">Cadd9(omit3)<"),
      ("1M7(9,omit3)", ">CM7(9,omit3)<"),
      ("6m7omit5/5", ">Am7(omit5)/G<"),
      ("5omit3@red", ">G(omit3)<"),
    ] {
    let (src, expected) = pair
    let html = shown(src)
    if !html.contains(expected) {
      fail("expected " + expected + " in " + html)
    }
  }
  // ディグリー表示も同じ(ローマ数字 + 括弧)
  let degree = @chord_language.render_widget_html("| 1add9omit3 |")
  assert_true(degree.contains("Iadd9(omit3)"))
}

///|
test "omit: playback leaves out the third or the fifth" {
  // C(omit3) = C と G だけ。C = C E G と違う
  assert_true(played("| 1omit3 |") != played("| 1 |"))
  // C(omit3) はパワーコード C5 と同じ音
  assert_eq(played("| 1omit3 |"), played("| 15 |"))
  // Cadd9(omit3) は C D G(sus2 と同じ構成音)。C7(omit5) は 5 度を抜く
  assert_eq(played("| 1add9omit3 |").contains("64"), false) // E4 を鳴らさない
  assert_true(played("| 17omit5 |") != played("| 17 |"))
  assert_eq(played("| 17omit5 |").contains("67"), false) // G4 を鳴らさない
}

///|
test "omit: errors" {
  // 度数は 3 か 5 だけ
  assert_eq(first_error("| 1omit7 |"), "InvalidOmitDegree")
  assert_eq(first_error("| 1(omit1) |"), "InvalidOmitDegree")
  assert_eq(first_error("| 1omit |"), "InvalidOmitDegree")
  // sus は 3 度を、b5 / #5 は 5 度を変えるので、同じ度数の omit と一緒に使えない
  assert_eq(first_error("| 1sus4omit3 |"), "ConflictingOmit")
  assert_eq(first_error("| 1(sus4,omit3) |"), "ConflictingOmit")
  assert_eq(first_error("| 17b5omit5 |"), "ConflictingOmit")
  assert_eq(first_error("| 17(#5,omit5) |"), "ConflictingOmit")
  // 違う度数なら使える
  assert_eq(first_error("| 1sus4omit5 |"), "none")
  assert_eq(first_error("| 17b5omit3 |"), "none")
  // パワーコード・4 度堆積には付けられない(従来どおり)
  assert_eq(first_error("| 15omit3 |"), "InvalidPowerChordCombination")
  assert_eq(first_error("| 1qomit5 |"), "InvalidQuartalCombination")
}

///|
test "omit: json and highlight" {
  assert_true(
    omit_ast("1omit3").contains("{\"type\":\"omit\",\"degree\":\"3\"}"),
  )
  // 括弧なしの omit も、テンションと同じ色(tension)
  let spans = @chord_language.highlight_spans("1add9omit3")
  assert_true(spans.contains("\"tension\""))
}
