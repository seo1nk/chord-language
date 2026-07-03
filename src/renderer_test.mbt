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
      #|<div class="chord-error"><div class="chord-error-msg">ParseError: Invalid degree '8' (must be 1-7) in '8x' at line 2</div><pre class="chord-error-src">1 3m7
      #|8x 5</pre></div>
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
