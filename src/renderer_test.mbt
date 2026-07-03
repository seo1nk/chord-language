///|
/// HTML レンダラのゴールデンテスト（Phase 3 の AST/エラー型変更に対する回帰検出面）
test "render basic score to html" {
  inspect(
    @chord_language.parse_to_html("1 3m7 | 4M7 5"),
    content=(
      #|<div class="chord-score"><div class="chord-line"><span class="chord-cell chord">I</span><span class="chord-cell chord">IIIm7</span><span class="chord-cell chord-barline"></span><span class="chord-cell chord">IVM7</span><span class="chord-cell chord">V</span></div></div>
    ),
  )
}

///|
/// 色アノテーションが CSS クラスとして出力される
test "render colored chords to html" {
  inspect(
    @chord_language.parse_to_html("1@red 3m7@blue 5@green"),
    content=(
      #|<div class="chord-score"><div class="chord-line"><span class="chord-cell chord chord--red">I</span><span class="chord-cell chord chord--blue">IIIm7</span><span class="chord-cell chord chord--green">V</span></div></div>
    ),
  )
}

///|
/// 複数行・複雑なコード
test "render multiline score to html" {
  inspect(
    @chord_language.parse_to_html("s4M7(b5,b9)/b3 5 |\n2m7(b5) 1M7(sus4,9)"),
    content=(
      #|<div class="chord-score"><div class="chord-line"><span class="chord-cell chord">#IVM7(♭5,♭9)/♭III</span><span class="chord-cell chord">V</span><span class="chord-cell chord-barline"></span></div><div class="chord-line"><span class="chord-cell chord">IIm7(♭5)</span><span class="chord-cell chord">IM7(sus4,9)</span></div></div>
    ),
  )
}

///|
/// パース失敗時のフォールバック（行番号つきエラー + ソース表示、ページを壊さない）
test "render error fallback to html" {
  inspect(
    @chord_language.parse_to_html("1 3m7\n8x 5"),
    content=(
      #|<div class="chord-score"><div class="chord-line"><span class="chord-cell chord">I</span><span class="chord-cell chord">IIIm7</span></div><div class="chord-line chord-error"><span class="chord-error-msg">Invalid degree '8' (must be 1-7) in '8x' at line 2, position 0</span><pre class="chord-error-src">8x 5</pre></div></div>
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
      #|<div class="chord-score"><div class="chord-line"><span class="chord-cell chord">VI</span><span class="chord-cell chord">VII</span><span class="chord-cell chord">♭VII</span><span class="chord-cell chord">IM7(#9,11,#11,♭13,13)</span></div></div>
    ),
  )
}

///|
/// 1 行に複数エラーがある場合の埋め込み表示（メッセージが ; で連結される）
test "render multiple errors in one line" {
  inspect(
    @chord_language.parse_to_html("1M7() b9x"),
    content=(
      #|<div class="chord-score"><div class="chord-line chord-error"><span class="chord-error-msg">Empty parentheses are not allowed in '1M7()' at line 1, position 3; Invalid degree '9' (must be 1-7) in 'b9x' at line 1, position 7</span><pre class="chord-error-src">1M7() b9x</pre></div></div>
    ),
  )
}

///|
/// フロントマターつき入力の描画（meta は現状表示に影響しない）
test "render with frontmatter" {
  inspect(
    @chord_language.parse_to_html("---\nkey: G\n---\n1 4 5"),
    content=(
      #|<div class="chord-score"><div class="chord-line"><span class="chord-cell chord">I</span><span class="chord-cell chord">IV</span><span class="chord-cell chord">V</span></div></div>
    ),
  )
}
