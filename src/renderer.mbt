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
/// ディグリー → ローマ数字（表示用）
fn degree_roman(d : Degree) -> String {
  match d {
    D1 => "I"
    D2 => "II"
    D3 => "III"
    D4 => "IV"
    D5 => "V"
    D6 => "VI"
    D7 => "VII"
  }
}

///|
/// アクシデンタル → 記号（表示用: b→♭, s→#）
fn accidental_symbol(a : Accidental) -> String {
  match a {
    Sharp => "#"
    Flat => "♭"
  }
}

///|
fn tension_display(t : Tension) -> String {
  match t {
    FlatNine => "♭9"
    Nine => "9"
    SharpNine => "#9"
    Eleven => "11"
    SharpEleven => "#11"
    FlatThirteen => "♭13"
    Thirteen => "13"
  }
}

///|
fn alteration_display(a : Alteration) -> String {
  match a {
    FlatFive => "♭5"
    Sus(d) => "sus" + d.to_string()
  }
}

///|
fn option_display(opt : ChordOption) -> String {
  match opt {
    TensionOpt(t) => tension_display(t)
    AlterationOpt(a) => alteration_display(a)
  }
}

///|
/// ChordNode を表示用テキストに変換する。
/// ディグリーはローマ数字、アクシデンタルは ♭ / # 記号にする
/// （DSL 入力の 1-7 / b / s は変えない。あくまで表示層の変換）。
/// クオリティ・テンション等の表示位置の調整は Phase 4 で行う。
fn chord_display_text(node : ChordNode) -> String {
  let acc = match node.accidental {
    Some(a) => accidental_symbol(a)
    None => ""
  }
  let deg = degree_roman(node.degree)
  let qual = match node.quality {
    Some(Minor) => "m"
    Some(Diminish) => "dim"
    Some(Augment) => "aug"
    None => ""
  }
  let sev = match node.seventh {
    Some(Seventh) => "7"
    Some(MajorSeventh) => "M7"
    Some(Sixth) => "6"
    Some(Add(d)) => "add" + d.to_string()
    None => ""
  }
  let alt = match node.alteration {
    Some(a) => alteration_display(a)
    None => ""
  }
  let opts = if node.options.length() > 0 {
    "(" + node.options.map(option_display).join(",") + ")"
  } else {
    ""
  }
  let bass = match node.bass {
    Some(b) => {
      let b_acc = match b.accidental {
        Some(a) => accidental_symbol(a)
        None => ""
      }
      "/" + b_acc + degree_roman(b.degree)
    }
    None => ""
  }
  acc + deg + qual + sev + alt + opts + bass
}

///|
/// 1 行分のコード譜を HTML として書き出す（text_of でコードの表示テキストを差し替える）
fn write_line_html(
  sb : StringBuilder,
  line : Line,
  text_of : (ChordNode) -> String,
) -> Unit {
  sb.write_string("<div class=\"chord-line\">")
  for token in line.tokens {
    match token {
      Chord(node) => {
        let color_cls = match node.color {
          Some(c) => " chord--" + c.to_string()
          None => ""
        }
        sb.write_string("<span class=\"chord-cell chord" + color_cls + "\">")
        sb.write_string(escape_html(text_of(node)))
        sb.write_string("</span>")
      }
      BarLine =>
        sb.write_string("<span class=\"chord-cell chord-barline\"></span>")
    }
  }
  sb.write_string("</div>")
}

///|
/// エラー行を HTML として書き出す（行番号つきメッセージ + 該当ソース行）
fn write_error_line_html(
  sb : StringBuilder,
  errors : Array[ParseError],
  source_line : String?,
) -> Unit {
  sb.write_string("<div class=\"chord-line chord-error\">")
  sb.write_string("<span class=\"chord-error-msg\">")
  let msgs = errors.map(fn(e) { escape_html(e.message()) })
  sb.write_string(msgs.join("; "))
  sb.write_string("</span>")
  match source_line {
    Some(src) => {
      sb.write_string("<pre class=\"chord-error-src\">")
      sb.write_string(escape_html(src))
      sb.write_string("</pre>")
    }
    None => ()
  }
  sb.write_string("</div>")
}

///|
/// ScoreAST を HTML 文字列に変換する（表示テキスト関数を指定）
fn render_score_html(ast : ScoreAST, text_of : (ChordNode) -> String) -> String {
  let sb = StringBuilder::new()
  sb.write_string("<div class=\"chord-score\">")
  for line in ast.lines {
    write_line_html(sb, line, text_of)
  }
  sb.write_string("</div>")
  sb.to_string()
}

///|
/// ScoreAST を HTML 文字列に変換する（ディグリー表示・エラーなしの純粋な描画）
pub fn render_html(ast : ScoreAST) -> String {
  render_score_html(ast, chord_display_text)
}

///|
/// パース結果を HTML に変換する。エラー行は元の行位置に
/// エラーメッセージ + ソース行として埋め込み、正しい行は描画を続ける。
pub fn render_result_html(input : String, result : ParseResult) -> String {
  if result.errors.is_empty() {
    return render_html(result.score)
  }
  // 行番号 → Line / 行番号 → エラー列 のマップ
  let line_map : Map[Int, Line] = {}
  for line in result.score.lines {
    line_map[line.line_number] = line
  }
  let err_map : Map[Int, Array[ParseError]] = {}
  let global_errors : Array[ParseError] = []
  for e in result.errors {
    match e.line {
      Some(l) =>
        match err_map.get(l) {
          Some(arr) => arr.push(e)
          None => err_map[l] = [e]
        }
      None => global_errors.push(e)
    }
  }
  let src_lines = split_lines(input)
  let sb = StringBuilder::new()
  sb.write_string("<div class=\"chord-score\">")
  if global_errors.length() > 0 {
    write_error_line_html(sb, global_errors, None)
  }
  for idx in 0..<src_lines.length() {
    let line_no = idx + 1
    match line_map.get(line_no) {
      Some(line) => write_line_html(sb, line, chord_display_text)
      None => ()
    }
    match err_map.get(line_no) {
      Some(errs) => write_error_line_html(sb, errs, Some(src_lines[idx]))
      None => ()
    }
  }
  sb.write_string("</div>")
  sb.to_string()
}

///|
/// コード譜表示用の最小 CSS（.chord-score 配下にスコープ済み）。
/// リードシート風: コードは太字、小節線は縦線として描画する。
pub fn chord_css() -> String {
  (
    #|.chord-score { display: flex; flex-direction: column; gap: 0.6em; line-height: 1.5; padding: 0.5em 0; }
    #|.chord-line { display: flex; flex-wrap: wrap; column-gap: 1.1em; row-gap: 0.4em; align-items: center; }
    #|.chord-cell.chord { font-weight: 700; font-size: 1.15em; letter-spacing: 0.02em; font-family: Georgia, 'Times New Roman', serif; font-style: italic; }
    #|.chord-barline { display: inline-block; width: 2px; height: 1.7em; background: currentColor; opacity: 0.7; border-radius: 1px; user-select: none; }
    #|.chord--red { color: #d33636; }
    #|.chord--blue { color: #2563cc; }
    #|.chord--green { color: #1e9e50; }
    #|.chord-line.chord-error { display: flex; flex-direction: column; align-items: stretch; row-gap: 0.2em; border: 1px solid #d3363680; border-radius: 4px; padding: 0.4em 0.6em; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|.chord-error-msg { color: #d33636; font-size: 0.8em; }
    #|.chord-error-src { margin: 0; opacity: 0.75; white-space: pre-wrap; font-size: 0.9em; }
    #|.chord-widget { margin: 0.75em 0; }
    #|.chord-tabs { display: flex; gap: 0.4em; align-items: center; }
    #|.chord-tab { font: inherit; font-size: 0.78em; padding: 0.1em 0.75em; border: 1px solid #8886; border-radius: 999px; background: transparent; color: inherit; cursor: pointer; opacity: 0.65; }
    #|.chord-tab--active { opacity: 1; border-color: currentColor; font-weight: 600; }
    #|.chord-key-select { font: inherit; font-size: 0.78em; margin-left: auto; background: transparent; color: inherit; border: 1px solid #8886; border-radius: 4px; padding: 0.05em 0.3em; }
    #|.chord-widget[data-chord-active="degree"] .chord-panel--notes { display: none; }
    #|.chord-widget[data-chord-active="notes"] .chord-panel--degree { display: none; }
    #|.chord-widget[data-chord-active="degree"] .chord-key-select { visibility: hidden; }
    #|@media print { .chord-tabs { display: none; } }
  )
}

///|
/// 入力をパースして HTML を返す。エラーがあってもページを壊さず、
/// エラー行は元の行位置に行番号・位置つきメッセージ + ソース行として
/// 埋め込まれ、正しい行のコード譜は描画され続ける。
pub fn parse_to_html(input : String) -> String {
  render_result_html(input, parse(input))
}

///|
/// キープルダウンに載せるキー一覧（12 半音。表記は一般的なジャズチャート流儀:
/// フラット側は Db/Eb/Ab/Bb、F#/Gb はシャープ側を採用。D12 の暫定決定）
fn widget_keys() -> Array[String] {
  ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
}

///|
/// キー名の表示ラベル（b → ♭。# はそのまま）
fn key_display_label(key : String) -> String {
  key.replace_all(old="b", new="♭")
}

///|
/// 入力をパースし、指定キーの実音コード名でスコアを描画する。
/// パースエラーがある場合や不正なキー名の場合はディグリー表示（エラー埋め込み）に
/// フォールバックする。キー変更時のクライアント再レンダリング用 API。
pub fn parse_to_notes_html(input : String, key : String) -> String {
  let result = parse(input)
  if !result.errors.is_empty() {
    return render_result_html(input, result)
  }
  match parse_key_name(key) {
    Some(key_info) =>
      render_score_html(result.score, fn(node) {
        chord_note_text(node, key_info)
      })
    None => render_html(result.score)
  }
}

///|
/// タブ（ディグリー / コード）とキープルダウンを備えたウィジェット HTML を生成する。
/// SSR とライブプレビューの両方がこの単一ソースを使う（docs/chord.md v1.2 表示仕様）。
///
/// - デフォルトタブはディグリー（D11）
/// - コードタブの初期キーはフロントマターの key、未宣言なら C（既定値）
/// - キー変更時の再描画はクライアントランタイムが data-chord-src を
///   parse_to_notes_html に渡して行う
/// - パースエラーがある場合はタブなしのエラー埋め込み表示を返す
pub fn render_widget_html(input : String) -> String {
  let result = parse(input)
  if !result.errors.is_empty() {
    return render_result_html(input, result)
  }
  let initial_key = match result.score.meta {
    Some(meta) =>
      match meta.key {
        Some(k) => k
        None => "C"
      }
    None => "C"
  }
  let degree_panel = render_html(result.score)
  let notes_panel = match parse_key_name(initial_key) {
    Some(key_info) =>
      render_score_html(result.score, fn(node) {
        chord_note_text(node, key_info)
      })
    None => degree_panel
  }
  let sb = StringBuilder::new()
  sb.write_string(
    "<div class=\"chord-widget\" data-chord-active=\"degree\" data-chord-key=\"" +
    escape_html(initial_key) +
    "\" data-chord-src=\"" +
    escape_html(input) +
    "\">",
  )
  // タブとキープルダウン
  sb.write_string("<div class=\"chord-tabs\" role=\"tablist\">")
  sb.write_string(
    "<button type=\"button\" class=\"chord-tab chord-tab--active\" data-chord-tab=\"degree\">ディグリー</button>",
  )
  sb.write_string(
    "<button type=\"button\" class=\"chord-tab\" data-chord-tab=\"notes\">コード</button>",
  )
  sb.write_string("<select class=\"chord-key-select\" aria-label=\"キー\">")
  let keys = widget_keys()
  if !keys.contains(initial_key) {
    keys.push(initial_key)
  }
  for k in keys {
    let selected = if k == initial_key { " selected" } else { "" }
    sb.write_string(
      "<option value=\"" +
      escape_html(k) +
      "\"" +
      selected +
      ">" +
      escape_html(key_display_label(k)) +
      "</option>",
    )
  }
  sb.write_string("</select>")
  sb.write_string("</div>")
  // パネル
  sb.write_string("<div class=\"chord-panel chord-panel--degree\">")
  sb.write_string(degree_panel)
  sb.write_string("</div>")
  sb.write_string("<div class=\"chord-panel chord-panel--notes\">")
  sb.write_string(notes_panel)
  sb.write_string("</div>")
  sb.write_string("</div>")
  sb.to_string()
}
