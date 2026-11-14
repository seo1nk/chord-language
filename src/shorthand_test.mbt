///| 慣用表記の略記・#5・パワーコード(v1.4)

///|
/// 楽譜の中身(AST)だけを JSON にする
fn ast_json(input : String) -> String {
  let result = @chord_language.parse(input)
  let errors = result.errors.map(fn(e) { e.kind_name() }).join(",")
  result.score.to_json_value().stringify() + " errors=" + errors
}

///|
test "shorthand: tension chords mean the same as the explicit form" {
  let pairs : Array[(String, String)] = [
    ("59", "57(9)"),
    ("511", "57(11)"),
    ("513", "57(13)"),
    ("2m9", "2m7(9)"),
    ("2m11", "2m7(11)"),
    ("1M9", "1M7(9)"),
    ("1maj9", "1M7(9)"),
    ("4M13", "4M7(13)"),
    ("16/9", "16(9)"),
    ("169", "16(9)"),
    ("6m6/9", "6m6(9)"),
    ("59(b13)", "57(9,b13)"),
    ("59(9)", "57(9)"),
    ("b79sus4/1@red", "b77sus4(9)/1@red"),
    ("57#5", "57s5"),
    ("57(s5)", "57(#5)"),
  ]
  for pair in pairs {
    let explicit = ast_json(pair.1)
    assert_true(explicit.has_suffix(" errors="), msg="エラー: " + pair.1)
    assert_eq(ast_json(pair.0), explicit, msg=pair.0 + " = " + pair.1)
  }
}

///|
test "shorthand: names shown for the new forms" {
  inspect(
    @chord_language.parse_to_json("57(#5) 15 b75/3"),
    content=(
      #|{"success":true,"data":{"type":"ScoreBlock","lines":[{"line":1,"tokens":[{"type":"Chord","chord":{"degree":"5","seventh":{"type":"seventh","value":"7"},"options":[{"type":"s5"}]}},{"type":"Chord","chord":{"degree":"1","quality":"5"}},{"type":"Chord","chord":{"accidental":"b","degree":"7","quality":"5","bass":{"degree":"3"}}}]}]},"errors":[]}
    ),
  )
}

///|
test "shorthand: power chords take no seventh, sus or tensions" {
  for input in ["157", "15sus4", "15(9)", "15b5", "15M7"] {
    let result = @chord_language.parse(input)
    assert_eq(
      result.errors.map(fn(e) { e.kind_name() }).join(","),
      "InvalidPowerChordCombination",
      msg=input,
    )
  }
}

///|
test "shorthand: tension shorthand cannot be doubled with a seventh" {
  for input in ["59M7", "5137", "1M97"] {
    let result = @chord_language.parse(input)
    assert_eq(
      result.errors.map(fn(e) { e.kind_name() }).join(","),
      "DuplicateSeventh",
      msg=input,
    )
  }
}
