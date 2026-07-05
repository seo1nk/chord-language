///|
/// ChordAST → HTML レンダラ。
///
/// 表示の要点:
/// - コードスロットグリッド: 各コードを全行共通の等幅スロットに置き、
///   小節線はスロット境界の縦線として描画する（行をまたいだ縦の整列）
/// - ディグリーはローマ数字 + ♭/# 記号で表示（実音表示は transpose.mbt）
/// - ウィジェット（render_widget_html）がタブ・キー選択・再生・画像コピーの
///   UI を単一ソースで生成し、SSR とライブプレビューの両方が使う
/// - 回帰検出のゴールデンテストは AST ではなく HTML 出力側に置くこと

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
/// コードスロット（グリッドの1マス）。小節線はスロット境界の縦線として描画する
priv enum SlotCell {
  ChordSlot(ChordNode, Bool) // (コード, 直前に小節線があるか)
  GroupSlot(Array[ChordNode], Bool) // - で連結された同一スロットのコード列
  RepeatSlot(Bool) // %（直前のコードの反復）
  NcSlot(Bool) // NC / N.C.（コードなし）
  BlankSlot(Bool) // _（空の拍。歌詞を割り当てられる）
  EmptySlot(Bool) // 空小節のプレースホルダ（|| など。歌詞は消費しない）
}

///|
/// 行のトークンをコードスロット列に変換する。
/// 返り値: (行頭に小節線があるか, スロット列, 行末に小節線があるか)
fn line_slots(tokens : Array[Token]) -> (Bool, Array[SlotCell], Bool) {
  let slots : Array[SlotCell] = []
  let mut bar_pending = false
  let mut leading = false
  let mut first = true
  for token in tokens {
    match token {
      BarLine => {
        if first {
          leading = true
        } else if bar_pending {
          slots.push(EmptySlot(true))
        } else {
          bar_pending = true
        }
        first = false
      }
      Chord(n) => {
        slots.push(ChordSlot(n, bar_pending))
        bar_pending = false
        first = false
      }
      ChordGroup(nodes) => {
        slots.push(GroupSlot(nodes, bar_pending))
        bar_pending = false
        first = false
      }
      Repeat => {
        slots.push(RepeatSlot(bar_pending))
        bar_pending = false
        first = false
      }
      NoChord => {
        slots.push(NcSlot(bar_pending))
        bar_pending = false
        first = false
      }
      EmptyBeat => {
        slots.push(BlankSlot(bar_pending))
        bar_pending = false
        first = false
      }
    }
  }
  (leading, slots, bar_pending)
}

///|
/// 1 行分のコード譜をコードスロットのグリッドとして書き出す。
/// スロットはスコア全体で共通の列ラスタ（--chord-cols）に載るため、
/// 行が違っても同じ位置のコード同士が縦に揃う。
/// 小節線（|）はスロット境界の縦線として描画される。
fn write_line_html(
  sb : StringBuilder,
  line : Line,
  text_of : (ChordNode) -> String,
) -> Unit {
  let (leading, slots, trailing) = line_slots(line.tokens)
  let mut cls = "chord-line"
  if leading {
    cls = cls + " chord-line--start-bar"
  }
  if trailing {
    cls = cls + " chord-line--end-bar"
  }
  sb.write_string("<div class=\"" + cls + "\">")
  // 歌詞断片をスロット順に取り出すカーソル（空スロットは消費しない）
  let mut lyric_idx = 0
  let lyric_of = fn() -> String? {
    let frag = if lyric_idx < line.lyrics.length() {
      line.lyrics[lyric_idx]
    } else {
      None
    }
    lyric_idx = lyric_idx + 1
    frag
  }
  for slot in slots {
    match slot {
      ChordSlot(node, bar_before) => {
        let color_cls = match node.color {
          Some(c) => " chord--" + c.to_string()
          None => ""
        }
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord" + color_cls + bar_cls + "\">",
        )
        sb.write_string(escape_html(text_of(node)))
        write_lyric_html(sb, lyric_of())
        sb.write_string("</span>")
      }
      GroupSlot(nodes, bar_before) => {
        // 1 スロットを複数コードで共有し、等間隔で幅を埋める（八分音符的な拍位置の表現）
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord-group" + bar_cls + "\">",
        )
        // 歌詞断片が - でグループ数どおりに分割できる場合は各コードに配る
        let member_lyrics : Array[String?] = []
        match lyric_of() {
          Some(text) => {
            let parts = text.split("-").map(fn(v) { v.to_owned() }).to_array()
            if parts.length() == nodes.length() {
              for part in parts {
                member_lyrics.push(Some(part))
              }
            } else {
              member_lyrics.push(Some(text))
              for _i in 1..<nodes.length() {
                member_lyrics.push(None)
              }
            }
          }
          None =>
            for _i in 0..<nodes.length() {
              member_lyrics.push(None)
            }
        }
        for i, node in nodes {
          let color_cls = match node.color {
            Some(c) => " chord--" + c.to_string()
            None => ""
          }
          sb.write_string("<span class=\"chord" + color_cls + "\">")
          sb.write_string(escape_html(text_of(node)))
          write_lyric_html(sb, member_lyrics[i])
          sb.write_string("</span>")
        }
        sb.write_string("</span>")
      }
      RepeatSlot(bar_before) => {
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord chord-repeat" + bar_cls + "\">%",
        )
        write_lyric_html(sb, lyric_of())
        sb.write_string("</span>")
      }
      NcSlot(bar_before) => {
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord chord-nc" + bar_cls + "\">N.C.",
        )
        write_lyric_html(sb, lyric_of())
        sb.write_string("</span>")
      }
      BlankSlot(bar_before) => {
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord-cell--blank" + bar_cls + "\">",
        )
        write_lyric_html(sb, lyric_of())
        sb.write_string("</span>")
      }
      EmptySlot(bar_before) => {
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord-cell--empty" + bar_cls + "\"></span>",
        )
      }
    }
  }
  sb.write_string("</div>")
}

///|
/// 歌詞断片をコードの下に書き出す（None は何も出さない）
fn write_lyric_html(sb : StringBuilder, frag : String?) -> Unit {
  match frag {
    Some(text) => {
      sb.write_string("<span class=\"chord-lyric\">")
      sb.write_string(escape_html(text))
      sb.write_string("</span>")
    }
    None => ()
  }
}

///|
/// セクションラベルを書き出す
fn write_section_html(sb : StringBuilder, sec : SectionLabel) -> Unit {
  // 白抜き反転バッジ: 外側の background: currentColor は親から継承した文字色、
  // 内側の span がページ背景色で文字を抜く（同一要素だと currentColor が循環するため分離）
  sb.write_string(
    "<div class=\"chord-section\"><span class=\"chord-section-name\">",
  )
  sb.write_string(escape_html(sec.name))
  sb.write_string("</span></div>")
}

///|
/// スコア全体のスロット列数（グリッドの列ラスタ）を求める
fn score_slot_cols(ast : ScoreAST) -> Int {
  let mut cols = 1
  for line in ast.lines {
    let (_, slots, _) = line_slots(line.tokens)
    if slots.length() > cols {
      cols = slots.length()
    }
  }
  cols
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
  let cols = score_slot_cols(ast)
  let sb = StringBuilder::new()
  sb.write_string(
    "<div class=\"chord-score\" style=\"--chord-cols:" +
    cols.to_string() +
    "\">",
  )
  let mut si = 0
  for line in ast.lines {
    while si < ast.sections.length() &&
          ast.sections[si].line_number < line.line_number {
      write_section_html(sb, ast.sections[si])
      si = si + 1
    }
    write_line_html(sb, line, text_of)
  }
  while si < ast.sections.length() {
    write_section_html(sb, ast.sections[si])
    si = si + 1
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
  let section_map : Map[Int, SectionLabel] = {}
  for sec in result.score.sections {
    section_map[sec.line_number] = sec
  }
  let src_lines = split_lines(input)
  let cols = score_slot_cols(result.score)
  let sb = StringBuilder::new()
  sb.write_string(
    "<div class=\"chord-score\" style=\"--chord-cols:" +
    cols.to_string() +
    "\">",
  )
  if global_errors.length() > 0 {
    write_error_line_html(sb, global_errors, None)
  }
  for idx in 0..<src_lines.length() {
    let line_no = idx + 1
    match section_map.get(line_no) {
      Some(sec) => write_section_html(sb, sec)
      None => ()
    }
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
    #|.chord-score { display: grid; grid-template-columns: repeat(var(--chord-cols), minmax(max-content, 1fr)); row-gap: 1.35em; line-height: 1.5; padding: 0.6em 0; --chord-cols: 4; --chord-barline: 1.5px solid rgba(136, 136, 136, 0.75); }
    #|.chord-line { grid-column: 1 / -1; display: grid; grid-template-columns: repeat(var(--chord-cols), minmax(max-content, 1fr)); align-items: stretch; }
    #|@supports (grid-template-columns: subgrid) { .chord-line { grid-template-columns: subgrid; } }
    #|.chord-cell { display: block; padding: 0.25em 0.9em 0.25em 0.75em; min-height: 1.4em; min-width: 0; }
    #|.chord-cell--bar-before { border-left: var(--chord-barline); }
    #|.chord-line--start-bar .chord-cell:first-child { border-left: var(--chord-barline); }
    #|.chord-line--end-bar .chord-cell:last-child { border-right: var(--chord-barline); }
    #|.chord-score .chord { font-weight: 500; font-size: 1.06em; letter-spacing: 0.015em; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Hiragino Sans', 'Helvetica Neue', Arial, sans-serif; font-style: normal; white-space: nowrap; }
    #|.chord-cell.chord-group { display: flex; align-items: baseline; column-gap: 0.5em; }
    #|.chord-cell.chord-group > .chord { flex: 1 1 0; min-width: max-content; }
    #|.chord-repeat { opacity: 0.7; }
    #|.chord-nc { opacity: 0.85; }
    #|.chord-cell--blank .chord-lyric { margin-top: 1.55em; }
    #|.chord-widget, .chord-score { --chord-bg: #ffffff; }
    #|:root[data-theme="dark"] .chord-widget, :root[data-theme="dark"] .chord-score { --chord-bg: #0d1117; }
    #|@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) .chord-widget, :root:not([data-theme="light"]) .chord-score { --chord-bg: #0d1117; } }
    #|.chord-section { grid-column: 1 / -1; justify-self: start; font-size: 0.78em; font-weight: 700; letter-spacing: 0.06em; background: currentColor; border-radius: 3px; padding: 0.12em 0.7em; margin-bottom: -0.5em; }
    #|.chord-section-name { color: var(--chord-bg); }
    #|.chord-lyric { display: block; font-weight: 400; font-size: 0.72em; letter-spacing: 0; opacity: 0.88; margin-top: 0.15em; white-space: nowrap; }
    #|.chord--red { color: #d33636; }
    #|.chord--blue { color: #2563cc; }
    #|.chord--green { color: #1e9e50; }
    #|.chord-line.chord-error { display: flex; flex-direction: column; align-items: stretch; row-gap: 0.2em; border: 1px solid #d3363680; border-radius: 4px; padding: 0.4em 0.6em; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|.chord-error-msg { color: #d33636; font-size: 0.8em; }
    #|.chord-error-src { margin: 0; opacity: 0.75; white-space: pre-wrap; font-size: 0.9em; }
    #|.chord-widget { margin: 0.75em 0; border-bottom: 1.5px solid #88888866; padding-bottom: 0.6em; }
    #|.chord-tabs { display: flex; align-items: flex-end; gap: 0.3em; border-bottom: 1.5px solid #88888866; padding: 0 0.5em; }
    #|.chord-tab { font: inherit; font-size: 0.78em; padding: 0.3em 1.1em; border: 1.5px solid transparent; border-bottom: none; border-radius: 8px 8px 0 0; background: transparent; color: inherit; cursor: pointer; opacity: 0.6; margin-bottom: 0; }
    #|.chord-tab--active { opacity: 1; font-weight: 600; border-color: #88888866; background: var(--chord-bg); margin-bottom: -1.5px; }
    #|.chord-key-select { font: inherit; font-size: 0.78em; margin-left: auto; align-self: center; margin-bottom: 0.25em; background: transparent; color: inherit; border: 1px solid #8886; border-radius: 4px; padding: 0.05em 0.3em; }
    #|.chord-copy-img, .chord-play, .chord-help { font: inherit; font-size: 0.72em; align-self: center; margin-bottom: 0.25em; background: transparent; color: inherit; border: 1px solid #8886; border-radius: 4px; padding: 0.1em 0.6em; cursor: pointer; opacity: 0.75; }
    #|.chord-play { margin-left: 0.45em; }
    #|.chord-copy-img { margin-left: 0.45em; }
    #|.chord-help { margin-left: 0.45em; padding: 0.1em 0.5em; border-radius: 50%; }
    #|.chord-copy-img:hover, .chord-play:hover, .chord-help:hover { opacity: 1; }
    #|.chord-widget[data-chord-help="open"] .chord-help { opacity: 1; background: #8888883d; }
    #|.chord-cheatsheet { display: none; font-size: 0.78em; border: 1px solid #8886; border-radius: 6px; margin-top: 0.6em; padding: 0.6em 0.9em 0.75em; grid-template-columns: max-content 1fr; column-gap: 1.1em; row-gap: 0.28em; align-items: baseline; }
    #|.chord-widget[data-chord-help="open"] .chord-cheatsheet { display: grid; }
    #|.chord-cheatsheet code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.95em; white-space: nowrap; }
    #|.chord-cheatsheet span { opacity: 0.85; }
    #|.chord-cheat-head { grid-column: 1 / -1; font-weight: 700; font-size: 0.92em; opacity: 0.75; margin-top: 0.3em; }
    #|.chord-cheat-head:first-child { margin-top: 0; }
    #|.chord-cell--playing { background: #8888883d; border-radius: 5px; }
    #|.chord-widget[data-chord-active="degree"] .chord-panel--notes { display: none; }
    #|.chord-widget[data-chord-active="notes"] .chord-panel--degree { display: none; }
    #|.chord-widget[data-chord-active="degree"] .chord-key-select { visibility: hidden; }
    #|@media print { .chord-tabs, .chord-cheatsheet { display: none; } }
  )
}

///|
/// ウィジェットに埋め込む記法チートシート。ヘルプボタン（.chord-help）で開閉する。
/// 記法の変更時は docs/chord.md と合わせて必ず更新すること。
fn cheatsheet_html() -> String {
  (
    #|<div class="chord-cheatsheet">
    #|<div class="chord-cheat-head">コード（Key 基準のディグリーで書く）</div>
    #|<code>1</code><span>ディグリー 1〜7（Key: C なら 1=C, 6m=Am）</span>
    #|<code>#4 s4 b7</code><span>シャープ（# / s どちらでも）・フラット</span>
    #|<code>2m 4dim 5aug</code><span>マイナー / ディミニッシュ / オーギュメント</span>
    #|<code>17 1M7 1maj7 16 1add9</code><span>セブンス・シックス・add（M7 と maj7 は同じ）</span>
    #|<code>1M7(b9,#11)</code><span>テンションは括弧内にカンマ区切り</span>
    #|<code>1sus4 4M7(b5)</code><span>sus2/4/6・フラットファイブ</span>
    #|<code>3m/5</code><span>スラッシュベース</span>
    #|<code>b3@red</code><span>強調色（red / blue / green、末尾）</span>
    #|<div class="chord-cheat-head">スロット</div>
    #|<code>|</code><span>小節線</span>
    #|<code>%</code><span>直前のコードを繰り返す</span>
    #|<code>_</code><span>空拍（コードを伸ばす・歌詞だけ置く）</span>
    #|<code>NC</code><span>無音（N.C. も可）</span>
    #|<code>2-5</code><span>グループ: 1 スロットを複数コードで分け合う</span>
    #|<div class="chord-cheat-head">構成</div>
    #|<code>[Aメロ]</code><span>セクションラベル（単独行）</span>
    #|<code>&gt; ひかりの _ さきへ</code><span>直前のコード行への歌詞。空白 = 区切り、_ 単独 = 歌詞なし、断片中の _ = スペース</span>
    #|<code>key: Eb / bpm: 96 / time: 6/8</code><span>フロントマター（先頭に --- で囲んで書く。省略時 C・120・4/4）</span>
    #|</div>
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
/// フラット側は Db/Eb/Ab/Bb、F#/Gb はシャープ側を採用）
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
/// SSR とライブプレビューの両方がこの単一ソースを使う。
///
/// - デフォルトタブはディグリー
/// - コードタブの初期キーはフロントマターの key、未宣言なら C（既定値）
/// - キー変更・再生・画像コピーはクライアントランタイム（フォーク側
///   chord-widget.ts）が data 属性と公開 API（parse_to_notes_html /
///   parse_to_playback）を使って行う
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
  // 宣言キーが一覧と異名同音（例: C# と Db）の場合は、そのスロットを宣言の綴りで置き換える
  let keys = widget_keys()
  match parse_key_name(initial_key) {
    Some(ki) => {
      let pc = key_pitch_class(ki)
      let mut replaced = false
      for i in 0..<keys.length() {
        match parse_key_name(keys[i]) {
          Some(k2) =>
            if key_pitch_class(k2) == pc {
              keys[i] = initial_key
              replaced = true
              break
            }
          None => ()
        }
      }
      if !replaced {
        keys.push(initial_key)
      }
    }
    None => if !keys.contains(initial_key) { keys.push(initial_key) }
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
  sb.write_string(
    "<button type=\"button\" class=\"chord-play\" title=\"表示中のキーで再生\">▶ 再生</button>",
  )
  sb.write_string(
    "<button type=\"button\" class=\"chord-copy-img\" title=\"表示中の譜面を画像としてコピー\">画像コピー</button>",
  )
  sb.write_string(
    "<button type=\"button\" class=\"chord-help\" title=\"記法のチートシート\" aria-label=\"記法のチートシート\">?</button>",
  )
  sb.write_string("</div>")
  // チートシート（.chord-help でトグル。data-chord-help="open" で表示）
  sb.write_string(cheatsheet_html())
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
