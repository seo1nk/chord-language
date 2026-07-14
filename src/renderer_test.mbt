///|
/// HTML レンダラのゴールデンテスト（AST・エラー型変更に対する回帰検出面）
test "render basic score to html" {
  inspect(
    @chord_language.parse_to_html("1 3m7 | 4M7 5"),
    content=(
      #|<div class="chord-score" style="--chord-cols:4"><div class="chord-line"><span class="chord-cell chord">I</span><span class="chord-cell chord">IIIm7</span><span class="chord-cell chord chord-cell--bar-before">IVM7</span><span class="chord-cell chord">V</span></div></div>
    ),
  )
}

///|
/// 色アノテーションが CSS クラスとして出力される
test "render colored chords to html" {
  inspect(
    @chord_language.parse_to_html("1@red 3m7@blue 5@green"),
    content=(
      #|<div class="chord-score" style="--chord-cols:3"><div class="chord-line"><span class="chord-cell chord chord--red">I</span><span class="chord-cell chord chord--blue">IIIm7</span><span class="chord-cell chord chord--green">V</span></div></div>
    ),
  )
}

///|
/// 複数行・複雑なコード
test "render multiline score to html" {
  inspect(
    @chord_language.parse_to_html("s4M7(b5,b9)/b3 5 |\n2m7(b5) 1M7(sus4,9)"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line chord-line--end-bar"><span class="chord-cell chord">#IVM7(♭5,♭9)/♭III</span><span class="chord-cell chord">V</span></div><div class="chord-line"><span class="chord-cell chord">IIm7(♭5)</span><span class="chord-cell chord">IM7(sus4,9)</span></div></div>
    ),
  )
}

///|
/// パース失敗時のフォールバック（行番号つきエラー + ソース表示、ページを壊さない）
test "render error fallback to html" {
  inspect(
    @chord_language.parse_to_html("1 3m7\n8x 5"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line"><span class="chord-cell chord">I</span><span class="chord-cell chord">IIIm7</span></div><div class="chord-line chord-error"><span class="chord-error-msg">不正なディグリー '8'(1〜7 で書きます) — '8x'(2 行目, 位置 0)</span><pre class="chord-error-src">8x 5</pre></div></div>
    ),
  )
}

///|
/// エラーフォールバックの HTML エスケープ（XSS 防止）
test "render error escapes html in source" {
  let html = @chord_language.parse_to_html("<script>alert(1)</script>")
  assert_true(html.contains("&lt;script&gt;"))
  assert_true(!html.contains("<script>"))
}

///|
/// CSS がスコープ済みセレクタのみを含む
test "chord css is scoped" {
  let css = @chord_language.chord_css()
  assert_true(css.contains(".chord-score"))
  assert_true(css.contains(".chord--red"))
}

///|
/// ローマ数字とテンション記号の表示網羅（VI/VII/♭VII、#9/11/#11/♭13/13）
test "render roman numerals and tension symbols" {
  inspect(
    @chord_language.parse_to_html("6 7 b7 1M7(s9,11,s11,b13,13)"),
    content=(
      #|<div class="chord-score" style="--chord-cols:4"><div class="chord-line"><span class="chord-cell chord">VI</span><span class="chord-cell chord">VII</span><span class="chord-cell chord">♭VII</span><span class="chord-cell chord">IM7(#9,11,#11,♭13,13)</span></div></div>
    ),
  )
}

///|
/// 1 行に複数エラーがある場合の埋め込み表示（メッセージが ; で連結される）
test "render multiple errors in one line" {
  inspect(
    @chord_language.parse_to_html("1M7() b9x"),
    content=(
      #|<div class="chord-score" style="--chord-cols:1"><div class="chord-line chord-error"><span class="chord-error-msg">空の括弧 () は使えません — '1M7()'(1 行目, 位置 3); 不正なディグリー '9'(1〜7 で書きます) — 'b9x'(1 行目, 位置 7)</span><pre class="chord-error-src">1M7() b9x</pre></div></div>
    ),
  )
}

///|
/// フロントマターつき入力の描画（meta は現状表示に影響しない）
test "render with frontmatter" {
  inspect(
    @chord_language.parse_to_html("---\nkey: G\n---\n1 4 5"),
    content=(
      #|<div class="chord-score" style="--chord-cols:3"><div class="chord-line"><span class="chord-cell chord">I</span><span class="chord-cell chord">IV</span><span class="chord-cell chord">V</span></div></div>
    ),
  )
}

///|
/// % 反復と - グループの描画
test "render repeat and group slots" {
  inspect(
    @chord_language.parse_to_html("6m7 3m/5 4m 2-5 | %"),
    content=(
      #|<div class="chord-score" style="--chord-cols:5"><div class="chord-line"><span class="chord-cell chord">VIm7</span><span class="chord-cell chord">IIIm/V</span><span class="chord-cell chord">IVm</span><span class="chord-cell chord-group"><span class="chord">II</span><span class="chord">V</span></span><span class="chord-cell chord chord-repeat chord-cell--bar-before">%</span></div></div>
    ),
  )
}

///|
/// セクションラベルと歌詞の描画（グループへの - 分配・% への歌詞含む）
test "render sections and lyrics" {
  inspect(
    @chord_language.parse_to_html(
      "[Aメロ]\n| 1M7 % | 2-5 |\n> ひかりの _ この-みち",
    ),
    content=(
      #|<div class="chord-score" style="--chord-cols:3"><div class="chord-section"><span class="chord-section-name">Aメロ</span></div><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord">IM7<span class="chord-lyric">ひかりの</span></span><span class="chord-cell chord chord-repeat">%</span><span class="chord-cell chord-group chord-cell--bar-before"><span class="chord">II<span class="chord-lyric">この</span></span><span class="chord">V<span class="chord-lyric">みち</span></span></span></div></div>
    ),
  )
}

///|
/// N.C. と空拍の描画（歌詞つき）
test "render nc and empty beats with lyrics" {
  inspect(
    @chord_language.parse_to_html(
      "| NC 1 _ % |\n> ワン トゥー _ フォー",
    ),
    content=(
      #|<div class="chord-score" style="--chord-cols:4"><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord chord-nc">N.C.<span class="chord-lyric">ワン</span></span><span class="chord-cell chord">I<span class="chord-lyric">トゥー</span></span><span class="chord-cell chord-cell--blank"></span><span class="chord-cell chord chord-repeat">%<span class="chord-lyric">フォー</span></span></div></div>
    ),
  )
}

///|
/// q(4度堆積)と m7-5(ハーフディミニッシュ)の表示
test "render quartal and half-diminished" {
  inspect(
    @chord_language.parse_to_html("1q 2m7-5"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line"><span class="chord-cell chord">Iq</span><span class="chord-cell chord">IIm7♭5</span></div></div>
    ),
  )
}

///|
/// インラインコード譜: 単一コード記号のインライン HTML(ホスト Markdown の :2m7: 用)
test "inline chord html renders single chord" {
  inspect(
    @chord_language.inline_chord_html("2m7"),
    content=(
      #|<span class="chord-inline">IIm7</span>
    ),
  )
  inspect(
    @chord_language.inline_chord_html("s4m7-5/b7"),
    content=(
      #|<span class="chord-inline">#IVm7♭5/♭VII</span>
    ),
  )
  inspect(
    @chord_language.inline_chord_html("b3@red"),
    content=(
      #|<span class="chord-inline chord--red">♭III</span>
    ),
  )
}

///|
/// インラインコード譜: 単一のコード記号としてパースできなければ空文字列
/// (呼び出し側が平文にフォールバックする契約)
test "inline chord html rejects non-chord tokens" {
  inspect(@chord_language.inline_chord_html(""), content="")
  inspect(@chord_language.inline_chord_html("smile"), content="")
  inspect(@chord_language.inline_chord_html("8"), content="")
  inspect(@chord_language.inline_chord_html("1 4"), content="")
  inspect(@chord_language.inline_chord_html("1M7x"), content="")
  inspect(@chord_language.inline_chord_html("%"), content="")
  inspect(@chord_language.inline_chord_html("NC"), content="")
}

///|
/// 転調バッジの描画: 単独行 = 全幅の .chord-modline、インライン = 次セルの
/// 前置チップ、行末 = 直前セルの後置チップ。スロット・列数は消費しない
test "render key change badges" {
  inspect(
    @chord_language.parse_to_html("[key: +1]\n| 1 4 | [key: F] 5 % |"),
    content=(
      #|<div class="chord-score" style="--chord-cols:4"><div class="chord-modline"><span class="chord-mod">key +1</span></div><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord">I<span class="chord-prevkey">=♭II</span></span><span class="chord-cell chord">IV<span class="chord-prevkey">=#IV</span></span><span class="chord-cell chord chord-cell--bar-before"><span class="chord-mod">F</span>V<span class="chord-prevkey">=VII</span></span><span class="chord-cell chord chord-repeat">%</span></div></div>
    ),
  )
  // 行末のインライン指示は最後のセルの後置チップ（段末の予告調号）
  inspect(
    @chord_language.parse_to_html("| 1 4 [key: +2] |"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord">I</span><span class="chord-cell chord">IV<span class="chord-mod chord-mod--after">+2</span></span></div></div>
    ),
  )
  // スコア末尾の宙吊り指示も消えずにバッジとして描画される
  inspect(
    @chord_language.parse_to_html("1\n[key: +1]"),
    content=(
      #|<div class="chord-score" style="--chord-cols:1"><div class="chord-line"><span class="chord-cell chord">I</span></div><div class="chord-modline"><span class="chord-mod">key +1</span></div></div>
    ),
  )
}

///|
/// エラーのある文書でも、正しい転調行はディグリー表示で描画され続ける
test "render key change with error lines" {
  inspect(
    @chord_language.parse_to_html("[key: +1]\n8x"),
    content=(
      #|<div class="chord-score" style="--chord-cols:1"><div class="chord-modline"><span class="chord-mod">key +1</span></div><div class="chord-line chord-error"><span class="chord-error-msg">不正なディグリー '8'(1〜7 で書きます) — '8x'(2 行目, 位置 0)</span><pre class="chord-error-src">8x</pre></div></div>
    ),
  )
}

///|
/// グループ内の _(空きパート)は空のセルとして間隔だけを占有する
test "render group holds" {
  inspect(
    @chord_language.parse_to_html("| 5-_-5-6 1 |"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord-group"><span class="chord">V</span><span class="chord chord-group-hold"></span><span class="chord">V</span><span class="chord">VI</span></span><span class="chord-cell chord">I</span></div></div>
    ),
  )
}

///|
/// 歌詞の拍分割: 断片中の - でスロットを等分し、書いた位置から歌詞が始まる
test "render lyric beat split" {
  // _-あいあい = 2 等分の後半(3 拍目)から。% や _ のスロットでも同様
  inspect(
    @chord_language.parse_to_html("| 1 % |\n> _-あいあい うえ-_"),
    content=(
      #|<div class="chord-score" style="--chord-cols:2"><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord">I<span class="chord-lyric chord-lyric--split"><span class="chord-lyric-beat"> </span><span class="chord-lyric-beat">あいあい</span></span></span><span class="chord-cell chord chord-repeat">%<span class="chord-lyric chord-lyric--split"><span class="chord-lyric-beat">うえ</span><span class="chord-lyric-beat"> </span></span></span></div></div>
    ),
  )
}

///|
/// 歌詞の拍分割はグループのパート数と一致しなくてよい
/// (不一致の分割はスロット全幅の等分割として置かれる)
test "render lyric split mismatched with group" {
  inspect(
    @chord_language.parse_to_html(
      "| 6m7 4M7 5-_-5-6 |\n> _空に向か う木々の _-よう",
    ),
    content=(
      #|<div class="chord-score" style="--chord-cols:3"><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord">VIm7<span class="chord-lyric"> 空に向か</span></span><span class="chord-cell chord">IVM7<span class="chord-lyric">う木々の</span></span><span class="chord-cell chord-group"><span class="chord">V</span><span class="chord chord-group-hold"></span><span class="chord">V</span><span class="chord">VI</span><span class="chord-lyric chord-lyric--split"><span class="chord-lyric-beat"> </span><span class="chord-lyric-beat">よう</span></span></span></div></div>
    ),
  )
}

///|
/// 転調前ディグリーの薄表示: チップの付いた小節だけに =V 形式で添える
/// (次の小節線で解除。単独行の転調は次の行の最初の小節に効く)
test "render previous-key degrees after modulation" {
  // key C → +2: 直後の小節の 4, 5 だけ =V, =VI(旧キー C の読み)。次の小節は出ない
  inspect(
    @chord_language.parse_to_html("| 1 | [key: +2] 4 5 | 1 |"),
    content=(
      #|<div class="chord-score" style="--chord-cols:4"><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord">I</span><span class="chord-cell chord chord-cell--bar-before"><span class="chord-mod">+2</span>IV<span class="chord-prevkey">=V</span></span><span class="chord-cell chord">V<span class="chord-prevkey">=VI</span></span><span class="chord-cell chord chord-cell--bar-before">I</span></div></div>
    ),
  )
  // 単独行の転調 → 次の行の最初の小節に効き、2 小節目からは出ない
  inspect(
    @chord_language.parse_to_html("[key: +1]\n| 4M7 5 | 1 |"),
    content=(
      #|<div class="chord-score" style="--chord-cols:3"><div class="chord-modline"><span class="chord-mod">key +1</span></div><div class="chord-line chord-line--start-bar chord-line--end-bar"><span class="chord-cell chord">IVM7<span class="chord-prevkey">=#IV</span></span><span class="chord-cell chord">V<span class="chord-prevkey">=♭VI</span></span><span class="chord-cell chord chord-cell--bar-before">I</span></div></div>
    ),
  )
}
