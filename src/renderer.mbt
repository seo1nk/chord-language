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
          sb.write_string(escape_html(chord_display_text(node)))
          sb.write_string("</span>")
        }
        BarLine =>
          sb.write_string("<span class=\"chord-cell chord-barline\"></span>")
      }
    }
    sb.write_string("</div>")
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
