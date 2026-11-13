///| テンポ変更 [bpm: 値] と拍子変更 [time: 値] のテスト(v1.3)。

///| 転調指示 [key: 値] と同じ「スロット・歌詞を消費しない指示」の枠に入る

///|
test "directive: bpm and time are parsed as tokens (standalone and inline)" {
  let json = @chord_language.parse_to_json("[bpm: 140]\n| 1 [time: 3/4] 4 |")
  assert_true(json.contains("\"success\":true"))
  assert_true(json.contains("{\"type\":\"TempoChange\",\"bpm\":140}"))
  assert_true(json.contains("{\"type\":\"TimeChange\",\"time\":\"3/4\"}"))
  // 空白の入れ方は [key: 値] と同じく自由
  let spaced = @chord_language.parse_to_json("[ bpm : 90 ] 1")
  assert_true(spaced.contains("\"bpm\":90"))
}

///|
test "directive: invalid values are errors with line and position" {
  let cases = [
    ("1 [bpm: 9999]", "InvalidTempo"),
    ("1 [bpm: fast]", "InvalidTempo"),
    ("1 [bpm:]", "InvalidTempo"),
    ("1 [bpm: 120", "InvalidTempo"),
    ("1 [time: 7/4]", "InvalidTimeSignature"),
    ("1 [time: ]", "InvalidTimeSignature"),
  ]
  for c in cases {
    let (input, kind) = c
    let json = @chord_language.parse_to_json(input)
    assert_true(json.contains("\"kind\":\"" + kind + "\""), msg=input)
    assert_true(json.contains("\"line\":1"), msg=input)
    // 位置は [ の位置(行内 0-indexed)
    assert_true(json.contains("\"position\":2"), msg=input)
  }
}

///|
test "directive: only lowercase key/bpm/time are directives; others stay section labels" {
  let upper = @chord_language.parse_to_json("[Bpm: 120]\n1")
  assert_true(
    upper.contains("\"sections\":[{\"line\":1,\"name\":\"Bpm: 120\"}]"),
  )
  let other = @chord_language.parse_to_json("[tempo: 120]\n1")
  assert_true(other.contains("\"name\":\"tempo: 120\""))
}

///|
test "directive: does not consume slots or lyrics" {
  let json = @chord_language.parse_to_json(
    "| 1 [bpm: 90] 4 [time: 3/4] | 5 |\n> あ い う",
  )
  assert_true(json.contains("\"success\":true"))
  // 列数は 3(指示はスロットにならない)
  let html = @chord_language.parse_to_html("| 1 [bpm: 90] 4 | 5 |")
  assert_true(html.contains("--chord-cols:3"))
}

///|
test "directive: chips in the score (standalone line and inline)" {
  let html = @chord_language.parse_to_html("[bpm: 140]\n| 1 [time: 3/4] 4 |")
  assert_true(
    html.contains(
      "<div class=\"chord-modline\"><span class=\"chord-mod chord-mod--tempo\">♩ = 140</span></div>",
    ),
  )
  assert_true(
    html.contains("<span class=\"chord-mod chord-mod--time\">3/4</span>IV"),
  )
  // 実音タブでも同じ表記
  let notes = @chord_language.parse_to_notes_html("[bpm: 140]\n1", "G")
  assert_true(notes.contains("♩ = 140"))
}

///|
test "directive: tempo change scales later beats to the opening tempo" {
  // 120 → 60(半分の速さ)。2 小節目は冒頭のテンポで 8 拍ぶんの長さになる
  let json = @chord_language.parse_to_playback(
    "---\nbpm: 120\n---\n1\n[bpm: 60]\n4", "C",
  )
  assert_true(json.contains("\"bpm\":120"))
  assert_true(json.contains("\"totalBeats\":12"))
  assert_true(json.contains("{\"beat\":0,\"dur\":4,\"notes\":[60,64,67]}"))
  assert_true(json.contains("{\"beat\":4,\"dur\":8,\"notes\":[65,69,72]}"))
  // ベースの刻みも同じく伸びる(1 拍 = 冒頭の 2 拍)
  assert_true(json.contains("{\"beat\":10,\"dur\":2,\"note\":41,\"gain\":1}"))
  // カーソルも同じ換算
  assert_true(json.contains("{\"beat\":4,\"dur\":8,\"cell\":1}"))
}

///|
test "directive: tempo change mid-line and a later change at the same position wins" {
  let json = @chord_language.parse_to_playback("1 [bpm: 240] [bpm: 60] 4", "C")
  // 既定 120 → 同じ位置で 240 → 60(あとの指定が有効)。2 小節目は 8 拍
  assert_true(json.contains("\"totalBeats\":12"))
  // テンポ変更が無いスコアは従来どおり
  let plain = @chord_language.parse_to_playback("1 4", "C")
  assert_true(plain.contains("\"totalBeats\":8"))
}

///|
test "directive: time change changes the bar length from that slot on" {
  let json = @chord_language.parse_to_playback("1\n[time: 3/4]\n4 5", "C")
  // 4 + 3 + 3
  assert_true(json.contains("\"totalBeats\":10"))
  assert_true(json.contains("{\"beat\":4,\"dur\":3,\"notes\":[65,69,72]}"))
  // 3/4 の小節はベース 3 打(最後の打は beat 6)
  assert_true(json.contains("{\"beat\":6,\"dur\":1,\"note\":41,\"gain\":1}"))
  assert_false(json.contains("{\"beat\":7,\"dur\":1,\"note\":41"))
}

///|
test "directive: switching to a compound meter starts the oom-pah-pah from there" {
  let json = @chord_language.parse_to_playback("1 [time: 6/8] 4", "C")
  // 1 小節目(4/4)にはスタブが無く、2 小節目(6/8 = 3 拍)から刻む
  assert_true(json.contains("\"totalBeats\":7"))
  assert_false(json.contains("\"stabs\":[]"))
  assert_true(json.contains("{\"beat\":4.5,\"dur\":0.5,\"notes\":[65,69,72]}"))
  assert_false(json.contains("{\"beat\":0.5,\"dur\":0.5"))
}

///|
test "directive: key, tempo and time can be combined" {
  let json = @chord_language.parse_to_playback(
    "1 [key: +2] [bpm: 60] [time: 2/4] 1", "C",
  )
  // 2 小節目は D の I、2/4 を半分の速さで = 冒頭の 4 拍
  assert_true(json.contains("{\"beat\":4,\"dur\":4,\"notes\":[62,66,69]}"))
  assert_true(json.contains("\"totalBeats\":8"))
}
