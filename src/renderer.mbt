///|
/// ChordAST → HTML の最小レンダラ（Phase 2 垂直スライス用）。
///
/// NOTE: 本レンダラは「使い捨て前提」の素朴な実装（docs/roadmap.md Phase 2 参照）。
/// レイアウト・表示品質の作り込みは Phase 4 で行う。
/// 回帰検出のゴールデンテストは AST ではなく HTML 出力側に置くこと。

///|
/// HTML エスケープ（テキストノード・属性値用）
fn escape_html(s : String) -> String {
  let sb = StringBuilder::new()
  for c in s {
    match c {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// ScoreAST を HTML 文字列に変換する
pub fn render_html(ast : ScoreAST) -> String {
  let sb = StringBuilder::new()
  sb.write_string("<div class=\"chord-score\">")
  for line in ast.lines {
    sb.write_string("<div class=\"chord-line\">")
    for token in line.tokens {
      match token {
        Chord(node) => {
          let color_cls = match node.color {
            Some(c) => " chord--" + c.to_string()
            None => ""
          }
          sb.write_string("<span class=\"chord-cell chord" + color_cls + "\">")
          sb.write_string(escape_html(chord_source_text(node)))
          sb.write_string("</span>")
        }
        BarLine =>
          sb.write_string("<span class=\"chord-cell chord-barline\">|</span>")
      }
    }
    sb.write_string("</div>")
  }
  sb.write_string("</div>")
  sb.to_string()
}

///|
/// コード譜表示用の最小 CSS（.chord-score 配下にスコープ済み）
pub fn chord_css() -> String {
  (
    #|.chord-score { display: flex; flex-direction: column; gap: 0.4em; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; line-height: 1.6; padding: 0.5em 0; }
    #|.chord-line { display: flex; flex-wrap: wrap; column-gap: 0.75em; row-gap: 0.3em; align-items: baseline; }
    #|.chord-cell.chord { font-weight: 600; }
    #|.chord-barline { opacity: 0.45; user-select: none; }
    #|.chord--red { color: #d33636; }
    #|.chord--blue { color: #2563cc; }
    #|.chord--green { color: #1e9e50; }
    #|.chord-error { border: 1px solid #d3363680; border-radius: 4px; padding: 0.5em 0.75em; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|.chord-error-msg { color: #d33636; font-size: 0.85em; margin-bottom: 0.4em; }
    #|.chord-error-src { margin: 0; opacity: 0.75; white-space: pre-wrap; }
  )
}

///|
/// 入力をパースして HTML を返す。パース失敗時はページを壊さず、
/// 行番号つきエラーメッセージ + ソースの <pre> 表示にフォールバックする。
pub fn parse_to_html(input : String) -> String {
  match parse(input) {
    Ok(ast) => render_html(ast)
    Err(e) =>
      "<div class=\"chord-error\"><div class=\"chord-error-msg\">" +
      escape_html(e.to_string()) +
      "</div><pre class=\"chord-error-src\">" +
      escape_html(input) +
      "</pre></div>"
  }
}
