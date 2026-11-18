///| 短調のキー(`key: Am`。v1.5)のテスト。

///| 要点: 数字の意味は長調と同じ(主音から数えた長音階の度数)。短調で変わるのは主音だけ。

///| いままでの相対長調の書き方(key: C で 6m)も、同じ音になる。

///|
fn notes(src : String, key : String) -> String {
  @chord_language.parse_to_notes_html(src, key)
}

///|
fn has(haystack : String, needle : String) -> Unit raise Error {
  if !haystack.contains(needle) {
    fail("expected to contain: " + needle + "\n--- in ---\n" + haystack)
  }
}

///|
fn lacks(haystack : String, needle : String) -> Unit raise Error {
  if haystack.contains(needle) {
    fail("expected not to contain: " + needle + "\n--- in ---\n" + haystack)
  }
}

///|
test "minor keys are accepted in the frontmatter" {
  for key in ["Am", "C#m", "Bbm", "Ebm", "G#m", "Abm", "Dm"] {
    let r = @chord_language.parse("---\nkey: " + key + "\n---\n| 1m b6 b7 5 |")
    assert_eq(r.errors.length(), 0)
  }
}

///|
test "minor key degrees count from the tonic like major keys" {
  // Am: 1m = Am、b6 = F、b7 = G、5 = E(長調と同じ数え方。m は書いたときだけ付く)
  let am = notes("| 1m b6 b7 5 | b3 4m 57 1 |", "Am")
  for chord in [">Am<", ">F<", ">G<", ">E<", ">C<", ">Dm<", ">E7<", ">A<"] {
    has(am, chord)
  }
  // C#m: 主音の綴りから解決する(b6 = A、5 = G#、b3 = E)
  let cs = notes("1m 4m b6 5 b3", "C#m")
  for chord in [">C#m<", ">F#m<", ">A<", ">G#<", ">E<"] {
    has(cs, chord)
  }
  // Ebm: 理論どおりの綴り(b6 = C♭、b7 = D♭、b3 = G♭)
  let eb = notes("1m b6 b7 b3", "Ebm")
  for chord in [">E♭m<", ">C♭<", ">D♭<", ">G♭<"] {
    has(eb, chord)
  }
}

///|
test "minor key and relative major give the same chords" {
  // いままでの書き方(相対長調)と、短調の書き方は、同じコード名になる
  let relative = notes("| 6m 4 5 6m |", "C")
  let minor = notes("| 1m b6 b7 1m |", "Am")
  assert_eq(relative, minor)
  // 再生も同じ音
  let src_relative = "---\nkey: C\n---\n| 6m 4 5 3 |"
  let src_minor = "---\nkey: Am\n---\n| 1m b6 b7 5 |"
  assert_eq(
    @chord_language.parse_to_playback(src_relative, "C"),
    @chord_language.parse_to_playback(src_minor, "Am"),
  )
}

///|
test "degree tab is unchanged in minor keys" {
  // ディグリー表示は数字どおり(Im ♭VI ♭VII)。キーのチップは key Am
  let html = @chord_language.render_widget_html(
    "---\nkey: Am\n---\n| 1m b6 b7 1m |",
  )
  for text in ["Im", "♭VI", "♭VII", "key Am"] {
    has(html, text)
  }
}

///|
test "widget lists minor keys for a minor block" {
  let html = @chord_language.render_widget_html(
    "---\nkey: Am\n---\n| 1m b6 b7 1m |",
  )
  has(html, "<option value=\"Am\" selected>Am</option>")
  for key in ["Cm", "C#m", "Ebm", "F#m", "G#m", "Bbm"] {
    has(html, "<option value=\"" + key + "\"")
  }
  lacks(html, "<option value=\"C\"")
  // 表示は b → ♭
  has(html, ">B♭m</option>")
  // 宣言キーが表と異名同音なら、そのスロットを宣言の綴りにする(D#m は Ebm の位置)
  let ds = @chord_language.render_widget_html("---\nkey: D#m\n---\n| 1m |")
  has(ds, "<option value=\"D#m\" selected>D#m</option>")
  lacks(ds, "<option value=\"Ebm\"")
  // 長調のブロックは、これまでどおり長調の 12 キー
  let major = @chord_language.render_widget_html("---\nkey: C\n---\n| 1 |")
  has(major, "<option value=\"C\" selected>C</option>")
  lacks(major, "<option value=\"Am\"")
}

///|
test "transposing a minor block keeps it minor" {
  let src = "---\nkey: Am\n---\n| 1m b6 b7 5 |"
  let em = notes(src, "Em")
  for chord in [">Em<", ">C<", ">D<", ">B<", "Key Em"] {
    has(em, chord)
  }
}

///|
test "modulations from and to minor keys" {
  // 相対の転調は短調のまま(Am +3 → Cm)。正準の綴り(+4 → C#m、+6 → Ebm)
  let rel = notes(
    "---\nkey: Am\n---\n| 1m |\n[key: +3]\n| 1m |\n[key: +1]\n| 1m |", "Am",
  )
  has(rel, "Key Cm (+3)")
  has(rel, "Key C#m (+1)")
  has(rel, ">C#m<")
  // 絶対の指示で、短調から長調へ(平行調・同主調)
  let abs = notes(
    "---\nkey: Am\n---\n| 1m |\n[key: C]\n| 1 |\n[key: A]\n| 1 |", "Am",
  )
  has(abs, "Key C")
  has(abs, ">C<")
  has(abs, "Key A<")
  // 長調から短調への絶対指示
  let to_minor = notes("---\nkey: C\n---\n| 1 |\n[key: Cm]\n| 1m b6 |", "C")
  has(to_minor, "Key Cm")
  has(to_minor, ">A♭<")
  // 移調しても、転調の幅と長調・短調は保たれる(Am → Bm で選ぶと、[key: C] は D になる)
  let moved = notes("---\nkey: Am\n---\n| 1m |\n[key: C]\n| 1 |", "Bm")
  has(moved, "Key D")
  has(moved, ">D<")
}

///|
test "spelling preference follows the selected minor key name" {
  // 表どおりの綴り(C#m)を選んだときは、転調先も既定の表(長調の F# +2 → Ab と同じ規則)
  let src = "---\nkey: Am\n---\n| 1m |\n[key: +2]\n| 1m |"
  has(notes(src, "C#m"), "Key E♭m (+2)")
  // あえて表と違う ♯ 側の綴り(A#m)を選ぶと、転調先も ♯ 側で綴る(+5 → D#m。既定なら Ebm)
  let up5 = "---\nkey: Am\n---\n| 1m |\n[key: +5]\n| 1m |"
  has(notes(up5, "A#m"), "Key D#m (+5)")
  has(notes(up5, "Bbm"), "Key E♭m (+5)")
}
