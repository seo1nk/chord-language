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

///|
/// 転調: 単独行（ラスサビ +1）— 以降のディグリーが新キー基準になる
test "transpose key change standalone" {
  inspect(
    @chord_language.parse_to_notes_html("1 4\n[key: +1]\n1 4", "C"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line"><span class="chord-cell chord">C</span><span class="chord-cell chord">F</span></div><div class="chord-modline"><span class="chord-mod">Key D♭ (+1)</span></div><div class="chord-line"><span class="chord-cell chord">D♭</span><span class="chord-cell chord">G♭</span></div></div>
    ),
  )
}

///|
/// 転調: インライン（2 小節ごと +2 の合成。C → D → E）
test "transpose key change inline" {
  inspect(
    @chord_language.parse_to_notes_html(
      "| 1 | [key: +2] 1 | [key: +2] 1 |", "C",
    ),
    content=(
      #|<div class="chord-score" style="--chord-cols:3"><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord">C</span><span class="chord-cell chord chord-cell--bar-before"><span class="chord-mod">D</span>D</span><span class="chord-cell chord chord-cell--bar-before"><span class="chord-mod">E</span>E</span></div></div>
    ),
  )
}

///|
/// プルダウン移調 = 初期キーの差し替え: δ は文中の絶対キー指定にも一様に適用
/// （宣言 C・選択 D → δ=+2。[key: F] は実効 G になる）
test "transpose key change delta on absolute" {
  inspect(
    @chord_language.parse_to_notes_html("---\nkey: C\n---\n1\n[key: F]\n1", "D"),
    content=(
      #|<div class="chord-score" style="--chord-cols:1"><div class="chord-modline"><span class="chord-mod">Key D</span></div><div class="chord-line"><span class="chord-cell chord">D</span></div><div class="chord-modline"><span class="chord-mod">Key G</span></div><div class="chord-line"><span class="chord-cell chord">G</span></div></div>
    ),
  )
}

///|
/// δ=0 の絶対キー指定は原文の綴りを尊重する（C# は Db に正規化しない）
test "transpose key change spelling preserved" {
  inspect(
    @chord_language.parse_to_notes_html("[key: C#]\n1", "C"),
    content=(
      #|<div class="chord-score" style="--chord-cols:1"><div class="chord-modline"><span class="chord-mod">Key C#</span></div><div class="chord-line"><span class="chord-cell chord">C#</span></div></div>
    ),
  )
}

///|
/// 相対転調のスペリングは正準 12 キー表（E +1 → F、F# +2 → Ab）
test "transpose key change canonical spelling" {
  inspect(
    @chord_language.parse_to_notes_html("1\n[key: +1]\n1", "E"),
    content=(
      #|<div class="chord-score" style="--chord-cols:1"><div class="chord-line"><span class="chord-cell chord">E</span></div><div class="chord-modline"><span class="chord-mod">Key F (+1)</span></div><div class="chord-line"><span class="chord-cell chord">F</span></div></div>
    ),
  )
  inspect(
    @chord_language.parse_to_notes_html("1\n[key: +2]\n1", "F#"),
    content=(
      #|<div class="chord-score" style="--chord-cols:1"><div class="chord-line"><span class="chord-cell chord">F#</span></div><div class="chord-modline"><span class="chord-mod">Key A♭ (+2)</span></div><div class="chord-line"><span class="chord-cell chord">A♭</span></div></div>
    ),
  )
}

///|
/// 綴り優先度の伝播: 異名同音側の綴り(C#・Gb 等)を選ぶと、相対転調の
/// 転調先も同じ向きで綴る。既定表の綴り(Db・F# 等)は従来どおり既定表
test "spelling preference propagates to modulations" {
  // C#(♯側)を選択: +2 の転調先は Eb でなく D#
  let sharp = @chord_language.parse_to_notes_html("1\n[key: +2]\n1", "C#")
  assert_true(sharp.contains("Key D# (+2)"))
  assert_true(sharp.contains(">D#<"))
  // 既定綴りの Db は従来どおり ♭ 側
  let flat = @chord_language.parse_to_notes_html("1\n[key: +2]\n1", "Db")
  assert_true(flat.contains("Key E♭ (+2)"))
  // 既定表そのままの F# 選択も従来どおり(+2 → Ab)
  let default_spelling = @chord_language.parse_to_notes_html(
    "1\n[key: +2]\n1", "F#",
  )
  assert_true(default_spelling.contains("Key A♭ (+2)"))
  // Gb(♭側)を選択: pc6 へ戻る転調は F# でなく G♭ と綴る
  let flat_side = @chord_language.parse_to_notes_html(
    "1\n[key: +7]\n1\n[key: +5]\n1", "Gb",
  )
  assert_true(flat_side.contains("Key G♭ (+5)"))
  // 宣言キーが C# ならディグリータブの転調チップも ♯ 側で綴る
  let widget = @chord_language.render_widget_html(
    "---\nkey: C#\n---\n1\n[key: +2]\n1",
  )
  assert_true(widget.contains("key D# (+2)"))
}

///|
/// ウィジェットに ♯/♭ トグルが含まれる(切り替えの実体はランタイム)
test "widget has spelling toggle" {
  let html = @chord_language.render_widget_html("---\nkey: F\n---\n1")
  assert_true(html.contains("chord-spell"))
  assert_true(html.contains("aria-pressed=\"false\""))
}

///|
/// ダブルアクシデンタルの異名同音化: Db の b6 は 6(= B♭)をさらに
/// 半音下げた B♭♭ になるが、読めないので A と綴り直す(ルートと
/// スラッシュベースの両方)。シングルの変化音は理論綴りのまま
test "respell double accidentals" {
  let html = @chord_language.parse_to_notes_html("| b6 | 37/b6 |", "Db")
  assert_true(html.contains(">A<"))
  assert_true(html.contains("/A"))
  assert_false(html.contains("♭♭"))
  // F から -4 で Db に移った文脈でも同じ(ユーザー報告の再現)
  let modulated = @chord_language.parse_to_notes_html(
    "| 6m |\n[key: -4]\n| b6 |", "F",
  )
  assert_false(modulated.contains("♭♭"))
  // シングルの変化音は理論綴りを保つ(C の b3 = E♭)
  let single = @chord_language.parse_to_notes_html("| b3 |", "C")
  assert_true(single.contains("E♭"))
}

///|
/// ウィジェット: 両パネルとも解決後キー + 転調幅のチップ
/// （実音は "Key"、ディグリーは初期キーチップに合わせた小文字 "key"）
test "widget key change chips" {
  let html = @chord_language.render_widget_html(
    "---\nkey: G\n---\n1\n[key: +1]\n1",
  )
  assert_true(html.contains("Key A♭ (+1)")) // 実音パネル（G +1 → Ab）
  assert_true(html.contains("key A♭ (+1)")) // ディグリーパネル（宣言キー基準で解決）
}
