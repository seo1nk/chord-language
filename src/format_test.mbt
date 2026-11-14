///| 整形(format_score)と色付け(highlight_spans)のテスト(v1.3)

///|
/// 性質を確かめる入力の一覧(仕様書の例・エラー入り・歌詞・全角・指示・グループなど)
let format_corpus : Array[String] = [
  "1 3m7 4M7 5 | b7 1", "---\nkey:Eb\n  bpm :  96\n---\n[  サビ  ]\n| NC |\n> ぼく\n| 1(9) b3@red 2m 37 |\n> の記憶 が_すべ て消えて も",
  "|1   4|  5 6 |   ", "[ key:+2 ] 1 [bpm:140]   [ time : 3/4 ] 4", "| 4M7 57 | 3m7 6m |\n> かぜが ふく まちの",
  "| 1 _ 4-5 6m | NC 2m7-5 1 % |\n> a _ b-c", "| 1   8x  |  \n> あ い", "5-_-5-6 1M7(b9, s11)\n> _-よう",
  "", "\n\n| 1 |\n\n", "---\nkey: C\n| 1 |", "1\n> 歌詞が 多すぎる 行 です",
  "[key: H] 1   4", "1 [bpm: 9999]   4", "|1 8x|4||  \n> あ い", "  1 8x|  (b9|) 4",
  "[key: +2 | 1 8x", "| 1 [bpm:9999]|4",
]

///|
/// 整形で変わってはいけない部分(楽譜の中身と、エラーの種類・行・トークン)。
/// エラーの桁位置とメッセージ中の桁は、小節線の前後の空白で動いてよい
fn format_meaning(input : String) -> String {
  let result = @chord_language.parse(input)
  let errors = result.errors.map(fn(e) {
    let line = match e.line {
      Some(l) => l.to_string()
      None => "-"
    }
    let token = match e.token {
      Some(t) => t
      None => "-"
    }
    e.kind_name() + "@" + line + ":" + token
  })
  result.score.to_json_value().stringify() + "\n" + errors.join("\n")
}

///|
test "format: keeps the line count, the meaning, and is idempotent" {
  for input in format_corpus {
    let out = @chord_language.format_score(input)
    assert_eq(
      out.split("\n").to_array().length(),
      input.split("\n").to_array().length(),
      msg="行数: " + input,
    )
    assert_eq(
      format_meaning(out),
      format_meaning(input),
      msg="意味: " + input,
    )
    assert_eq(@chord_language.format_score(out), out, msg="冪等: " + input)
  }
}

///|
test "format: spacing, directives, frontmatter, sections" {
  inspect(
    @chord_language.format_score("|1   4|  5 6 |   "),
    content="| 1 4 | 5 6 |",
  )
  inspect(
    @chord_language.format_score("[ key:+2 ] 1 [bpm:140]   [ time : 3/4 ] 4"),
    content="[key: +2] 1 [bpm: 140] [time: 3/4] 4",
  )
  inspect(
    @chord_language.format_score(
      "---\nkey:Eb\n  bpm :  96\n---\n[  サビ  ]\n1",
    ),
    content=(
      #|---
      #|key: Eb
      #|bpm: 96
      #|---
      #|[サビ]
      #|1
    ),
  )
}

///|
test "format: keeps the spelling of chords as written" {
  inspect(
    @chord_language.format_score("#4M7   s4maj7    2m7-5   1(b9,  s11)"),
    content="#4M7 s4maj7 2m7-5 1(b9,  s11)",
  )
}

///|
test "format: lines with errors keep their text, only bar lines get one space around" {
  inspect(
    @chord_language.format_score("| 1   8x  |  \n> あ   い  \n|1  4|"),
    content=(
      #|| 1   8x |
      #|> あ   い
      #|| 1 4 |
    ),
  )
  // 行頭の字下げは小節線の外側なので詰める。|| は | | になる。
  // 括弧の中の | と、小節線に接していない空白は書いたとおり
  inspect(
    @chord_language.format_score("  |1 8x||4  5|\n  1   8x|(b9|)  4"),
    content=(
      #|| 1 8x | | 4  5 |
      #|  1   8x | (b9|)  4
    ),
  )
}

///|
test "format: aligns lyrics under their slots (wide characters count as 2)" {
  inspect(
    @chord_language.format_score(
      "| 4M7 57 | 3m7 6m |\n> かぜが ふく まちの",
    ),
    content=(
      #|| 4M7    57   | 3m7    6m |
      #|> かぜが ふく   まちの
    ),
  )
  // コードの方が長ければ、歌詞の側を空けてそろえる
  inspect(
    @chord_language.format_score("| 1M7(9) 4 |\n> a b"),
    content=(
      #|| 1M7(9) 4 |
      #|> a      b
    ),
  )
  // 行頭に小節線が無い行は、歌詞の "> " のぶん字下げしてそろえる
  inspect(
    @chord_language.format_score("1 4\n> あ い"),
    content=(
      #|  1  4
      #|> あ い
    ),
  )
}

///|
test "highlight: chord parts, structure, lyrics and frontmatter" {
  inspect(
    @chord_language.highlight_spans(
      "---\nkey: Eb\n---\n[サビ]\n| b3m7(9)/5@red 2-5 % _ NC [bpm: 90] |\n> あ_い う-え",
    ),
    content=(
      #|[[1,0,3,"fence"],[2,0,3,"meta-key"],[2,5,7,"meta-value"],[3,0,3,"fence"],[4,0,4,"section"],[5,0,1,"bar"],[5,2,4,"degree"],[5,4,6,"quality"],[5,6,9,"tension"],[5,9,11,"bass"],[5,11,15,"color"],[5,16,17,"degree"],[5,17,18,"group"],[5,18,19,"degree"],[5,20,21,"repeat"],[5,22,23,"hold"],[5,24,26,"nc"],[5,27,36,"directive"],[5,37,38,"bar"],[6,0,1,"lyric-mark"],[6,2,3,"lyric"],[6,3,4,"lyric-hold"],[6,4,5,"lyric"],[6,6,7,"lyric"],[6,7,8,"lyric-split"],[6,8,9,"lyric"]]
    ),
  )
}

///|
test "highlight: the degree is one digit (57 = 5 + seventh)" {
  inspect(
    @chord_language.highlight_spans("57 b37"),
    content=(
      #|[[1,0,1,"degree"],[1,1,2,"quality"],[1,3,5,"degree"],[1,5,6,"quality"]]
    ),
  )
}

///|
test "highlight: half-diminished -5 is not split as a group, group holds are marked" {
  inspect(
    @chord_language.highlight_spans("2m7-5 5-_-1"),
    content=(
      #|[[1,0,1,"degree"],[1,1,5,"quality"],[1,6,7,"degree"],[1,7,8,"group"],[1,8,9,"hold"],[1,9,10,"group"],[1,10,11,"degree"]]
    ),
  )
}
