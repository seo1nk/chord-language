///| 実音変換（ディグリー + key → コード名）のテスト。

///| 異名同音のスペリング（F# キーの 7 = E# 等）が要点。

///|
/// key ごとの基本変換テーブル
test "transpose basic table" {
  // key C
  inspect(
    @chord_language.parse_to_notes_html("1 4 5 | b7 s4 3m7", "C"),
    content=(
      #|<div class="chord-score" style="--chord-cols:6"><div class="chord-line"><span class="chord-cell chord">C</span><span class="chord-cell chord">F</span><span class="chord-cell chord">G</span><span class="chord-cell chord chord-cell--bar-before">B♭</span><span class="chord-cell chord">F#</span><span class="chord-cell chord">Em7</span></div></div>
    ),
  )
  // key G: 1 4 5 → G C D、3m7 → Bm7、b7 → F
  inspect(
    @chord_language.parse_to_notes_html("1 4 5 3m7 b7", "G"),
    content=(
      #|<div class="chord-score" style="--chord-cols:5"><div class="chord-line"><span class="chord-cell chord">G</span><span class="chord-cell chord">C</span><span class="chord-cell chord">D</span><span class="chord-cell chord">Bm7</span><span class="chord-cell chord">F</span></div></div>
    ),
  )
}

///|
/// 異名同音のスペリング: シャープ系・フラット系キー
test "transpose enharmonic spelling" {
  // key F#: 7 は E#（F ではない）、3 は A#
  inspect(
    @chord_language.parse_to_notes_html("7 3", "F#"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line"><span class="chord-cell chord">E#</span><span class="chord-cell chord">A#</span></div></div>
    ),
  )
  // key Bb: 3 は D、4 は Eb、b3 は Db
  inspect(
    @chord_language.parse_to_notes_html("3 4 b3", "Bb"),
    content=(
      #|<div class="chord-score" style="--chord-cols:3"><div class="chord-line"><span class="chord-cell chord">D</span><span class="chord-cell chord">E♭</span><span class="chord-cell chord">D♭</span></div></div>
    ),
  )
  // key E: b6 は C、6 は C#
  inspect(
    @chord_language.parse_to_notes_html("b6 6", "E"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line"><span class="chord-cell chord">C</span><span class="chord-cell chord">C#</span></div></div>
    ),
  )
}

///|
/// 複雑なコード: クオリティ・テンション・ベース・色が引き継がれる
test "transpose complex chord" {
  // key G: s4M7(b5,b9)/b3@red → C#M7(♭5,♭9)/B♭ …ベース b3 は B♭
  inspect(
    @chord_language.parse_to_notes_html("s4M7(b5,b9)/b3@red", "G"),
    content=(
      #|<div class="chord-score" style="--chord-cols:1"><div class="chord-line"><span class="chord-cell chord chord--red">C#M7(♭5,♭9)/B♭</span></div></div>
    ),
  )
}

///|
/// ウィジェット HTML: タブ・キー select・両パネル・data 属性
test "render widget html" {
  let html = @chord_language.render_widget_html("---\nkey: G\n---\n1 4 5")
  // 初期キーとソースの data 属性
  assert_true(html.contains("data-chord-key=\"G\""))
  assert_true(html.contains("data-chord-active=\"degree\""))
  assert_true(html.contains("data-chord-src=\"---"))
  // タブ
  assert_true(html.contains("data-chord-tab=\"degree\""))
  assert_true(html.contains("data-chord-tab=\"notes\""))
  // ディグリーパネルとコードパネルの両方が含まれる
  assert_true(html.contains("chord-panel--degree"))
  assert_true(html.contains("chord-panel--notes"))
  assert_true(html.contains(">I<")) // ディグリー表示
  assert_true(html.contains(">G<")) // key=G の実音表示
  // キー select: G が selected、12 キー
  assert_true(html.contains("<option value=\"G\" selected>G</option>"))
  assert_true(html.contains("<option value=\"Bb\">B♭</option>"))
  // 画像コピーボタン
  assert_true(html.contains("chord-copy-img"))
}

///|
/// ウィジェット: key 未宣言なら既定値 C
test "widget defaults to key C" {
  let html = @chord_language.render_widget_html("1 4 5")
  assert_true(html.contains("data-chord-key=\"C\""))
  assert_true(html.contains("<option value=\"C\" selected>C</option>"))
  assert_true(html.contains(">C<")) // 実音パネルに C
}

///|
/// ウィジェット: パースエラー時はタブなしのエラー埋め込み表示
test "widget falls back on parse errors" {
  let html = @chord_language.render_widget_html("1 4\n8x")
  assert_true(!html.contains("chord-widget"))
  assert_true(html.contains("chord-error"))
}

///|
/// 不正なキー名の parse_to_notes_html はディグリー表示にフォールバック
test "notes html falls back on invalid key" {
  let html = @chord_language.parse_to_notes_html("1 4 5", "Zz")
  assert_true(html.contains(">I<"))
}

///|
/// 宣言キーが一覧と異名同音の場合、そのスロットを宣言の綴りで置き換える
/// （C# は Db の位置に入り、末尾に追加されない）
test "widget places enharmonic key in its slot" {
  let html = @chord_language.render_widget_html("---\nkey: C#\n---\n1 4 5")
  assert_true(html.contains("<option value=\"C#\" selected>C#</option>"))
  assert_true(!html.contains("value=\"Db\""))
  // C の直後（Db のスロット）に入っている
  assert_true(
    html.contains(
      "<option value=\"C\">C</option><option value=\"C#\" selected>C#</option><option value=\"D\">D</option>",
    ),
  )
  // Gb 宣言も F# のスロットに入る
  let html2 = @chord_language.render_widget_html("---\nkey: Gb\n---\n1")
  assert_true(html2.contains("<option value=\"Gb\" selected>G♭</option>"))
  assert_true(!html2.contains("value=\"F#\""))
}
