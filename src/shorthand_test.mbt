///| 括弧なしのテンション・#5・パワーコード(v1.4)

///|
/// 楽譜の中身(AST)だけを JSON にする
fn ast_json(input : String) -> String {
  let result = @chord_language.parse(input)
  let errors = result.errors.map(fn(e) { e.kind_name() }).join(",")
  result.score.to_json_value().stringify() + " errors=" + errors
}

///|
test "shorthand: tensions without parentheses mean the same as with them" {
  let pairs : Array[(String, String)] = [
    // 9 / 11 / 13 だけではセブンスを補わない
    ("59", "5(9)"),
    ("511", "5(11)"),
    ("513", "5(13)"),
    ("2m9", "2m(9)"),
    ("2m11", "2m(11)"),
    ("1dim9", "1dim(9)"),
    // セブンスを書けばセブンス入り
    ("579", "57(9)"),
    ("2m711", "2m7(11)"),
    ("1M79", "1M7(9)"),
    ("1maj713", "1M7(13)"),
    ("169", "16(9)"),
    ("6m69", "6m6(9)"),
    // いくつも続けて書ける
    ("57b9#11", "57(b9,#11)"),
    ("57b9s11b13", "57(b9,#11,b13)"),
    ("5913", "5(9,13)"),
    ("57b13", "57(b13)"),
    // 括弧と混ぜる(括弧なしが先。同じものは 1 つ)
    ("59(b13)", "5(9,b13)"),
    ("59(9)", "5(9)"),
    ("579(b13,9)", "57(9,b13)"),
    // オルタレーションの前にも後にも書ける
    ("b779sus4/1@red", "b77sus4(9)/1@red"),
    ("57sus4b9", "57sus4(b9)"),
    ("57b5b9", "57b5(b9)"),
    ("57#5#9", "57s5(s9)"),
    // M9 / maj9 などはメジャーセブンスを補う
    ("1M9", "1M7(9)"),
    ("1maj9", "1M7(9)"),
    ("4M13", "4M7(13)"),
    ("1maj11", "1M7(11)"),
    ("1M9#11", "1M7(9,#11)"),
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
test "shorthand: tensions are always shown in parentheses" {
  inspect(
    @chord_language.parse_to_html("59 579 2m11 1M9 169 57b9#11 57b5"),
    content=(
      #|<div class="chord-score" style="--chord-cols:7"><div class="chord-line"><span class="chord-cell chord">V(9)</span><span class="chord-cell chord">V7(9)</span><span class="chord-cell chord">IIm(11)</span><span class="chord-cell chord">IM7(9)</span><span class="chord-cell chord">I6(9)</span><span class="chord-cell chord">V7(♭9,#11)</span><span class="chord-cell chord">V7♭5</span></div></div>
    ),
  )
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
test "shorthand: a seventh cannot follow the tensions" {
  let cases : Array[(String, String)] = [
    ("1M97", "DuplicateSeventh"),
    ("579M7", "DuplicateSeventh"),
    ("5797", "DuplicateSeventh"),
    ("597", "UnrecognizedToken"),
    ("59M7", "UnrecognizedToken"),
    ("5137", "UnrecognizedToken"),
  ]
  for c in cases {
    let result = @chord_language.parse(c.0)
    assert_eq(
      result.errors.map(fn(e) { e.kind_name() }).join(","),
      c.1,
      msg=c.0,
    )
  }
}

///|
test "shorthand: the slash form 6/9 is not accepted (9 is not a bass degree)" {
  let result = @chord_language.parse("16/9")
  assert_eq(
    result.errors.map(fn(e) { e.kind_name() }).join(","),
    "InvalidDegree",
  )
}

///|
test "highlight: tensions without parentheses get the tension colour" {
  inspect(
    @chord_language.highlight_spans("579 57b9#11 1M9 1add9 57b5 2m11/5"),
    content=(
      #|[[1,0,1,"degree"],[1,1,2,"quality"],[1,2,3,"tension"],[1,4,5,"degree"],[1,5,6,"quality"],[1,6,8,"tension"],[1,8,11,"tension"],[1,12,13,"degree"],[1,13,15,"quality"],[1,16,17,"degree"],[1,17,21,"quality"],[1,22,23,"degree"],[1,23,26,"quality"],[1,27,28,"degree"],[1,28,29,"quality"],[1,29,31,"tension"],[1,31,33,"bass"]]
    ),
  )
}
