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
/// コード表記の共通サフィックス（クオリティ・セブンス・オルタレーション・括弧内）。
/// ディグリー表示（chord_display_text）と実音表示（chord_note_text）で共有する
/// （両者の違いはルートとベースの表記だけ）
fn chord_suffix_text(node : ChordNode) -> String {
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
  qual + sev + alt + opts
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
  acc + degree_roman(node.degree) + chord_suffix_text(node) + bass
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
/// 入力をパースして HTML を返す。エラーがあってもページを壊さず、
/// エラー行は元の行位置に行番号・位置つきメッセージ + ソース行として
/// 埋め込まれ、正しい行のコード譜は描画され続ける。
pub fn parse_to_html(input : String) -> String {
  render_result_html(input, parse(input))
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
