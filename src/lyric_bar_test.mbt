///| 歌詞の行の | (v1.7): 小節線の見た目に合わせて書いた | は区切りとして読み飛ばす

///|
fn lyric_errors(input : String) -> String {
  @chord_language.parse(input).errors.map(fn(e) { e.kind_name() }).join(",")
}

///|
fn degree_html(input : String) -> String {
  @chord_language.parse_to_html(input)
}

///|
test "lyric bars: bar lines in a lyric line are separators" {
  let with_bars = "| 2m7 57 | 1M7 67 |\n> きみと | みた | そら | いろ |"
  let plain = "| 2m7 57 | 1M7 67 |\n> きみと みた そら いろ"
  assert_eq(lyric_errors(with_bars), "")
  assert_eq(degree_html(with_bars), degree_html(plain))
  // 空白なしでくっつけても区切りになる
  assert_eq(
    degree_html("| 2m7 57 | 1M7 67 |\n> きみと|みた|そら|いろ"),
    degree_html(plain),
  )
  // 行頭の | も、ただの区切り
  assert_eq(
    degree_html("| 2m7 57 | 1M7 67 |\n> | きみと みた | そら いろ |"),
    degree_html(plain),
  )
  // _ や拍分割の - はこれまでどおり
  assert_eq(
    degree_html("| 2m7 57 | 1M7 67 |\n> _ _-みた | そら _ |"),
    degree_html("| 2m7 57 | 1M7 67 |\n> _ _-みた そら _"),
  )
}

///|
test "lyric bars: too many fragments is still an error, counted without bars" {
  assert_eq(
    lyric_errors("| 1 4 |\n> あ | い | う |"),
    "TooManyLyricFragments",
  )
  assert_eq(lyric_errors("| 1 4 |\n> あ | い |"), "")
}

///|
test "lyric bars: format keeps bars under the chord bar lines" {
  // 歌詞の行に | があれば、コード行の小節線の真下にそろえ直す
  inspect(
    @chord_language.format_score(
      "| 2m7 57 | 1M7 67 |\n> きみと|みた | そら  いろ|",
    ),
    content=(
      #|| 2m7    57   | 1M7  67   |
      #|> きみと みた | そら いろ |
    ),
  )
  // | が無ければ、これまでどおり | は足さない
  inspect(
    @chord_language.format_score(
      "| 2m7 57 | 1M7 67 |\n> きみと みた そら いろ",
    ),
    content=(
      #|| 2m7    57   | 1M7  67   |
      #|> きみと みた   そら いろ
    ),
  )
}

///|
test "lyric bars: highlight marks lyric bars as bar lines" {
  let spans = @chord_language.highlight_spans("| 1 4 |\n> あ | い")
  assert_true(spans.contains("[2,4,5,\"bar\"]"))
}
