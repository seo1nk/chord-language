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
    Some(Quartal) => "q"
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
  GroupSlot(Array[GroupPart], Bool) // - で連結された同一スロットのパート列(コード | _)
  RepeatSlot(Bool) // %（直前のコードの反復）
  NcSlot(Bool) // NC / N.C.（コードなし）
  BlankSlot(Bool) // _（空の拍。歌詞を割り当てられる）
  EmptySlot(Bool) // 空小節のプレースホルダ（|| など。歌詞は消費しない）
}

///|
/// 行のスロット分解結果。転調指示（[key: 値]）はスロットを消費しないため、
/// スロット列とは別に「各スロットの直前」「行末（最後のスロットより後）」の
/// 転調列として保持する（renderer と playback が同一経路で文書順に fold する）
priv struct LineSlots {
  leading : Bool // 行頭に小節線があるか
  slots : Array[SlotCell]
  trailing : Bool // 行末に小節線があるか
  keys_before : Array[Array[KeyChange]] // slots[i] の直前の転調指示（slots と同じ長さ）
  trailing_keys : Array[KeyChange] // 最後のスロットより後（行末）の転調指示
}

///|
/// 行のトークンをコードスロット列に変換する
fn line_slots(tokens : Array[Token]) -> LineSlots {
  let slots : Array[SlotCell] = []
  let keys_before : Array[Array[KeyChange]] = []
  let pending_keys : Array[KeyChange] = []
  let mut bar_pending = false
  let mut leading = false
  let mut first = true
  let push_slot = fn(cell : SlotCell) {
    slots.push(cell)
    keys_before.push(pending_keys.copy())
    pending_keys.clear()
  }
  for token in tokens {
    match token {
      BarLine => {
        if first {
          leading = true
        } else if bar_pending {
          push_slot(EmptySlot(true))
        } else {
          bar_pending = true
        }
        first = false
      }
      Chord(n) => {
        push_slot(ChordSlot(n, bar_pending))
        bar_pending = false
        first = false
      }
      ChordGroup(nodes) => {
        push_slot(GroupSlot(nodes, bar_pending))
        bar_pending = false
        first = false
      }
      Repeat => {
        push_slot(RepeatSlot(bar_pending))
        bar_pending = false
        first = false
      }
      NoChord => {
        push_slot(NcSlot(bar_pending))
        bar_pending = false
        first = false
      }
      EmptyBeat => {
        push_slot(BlankSlot(bar_pending))
        bar_pending = false
        first = false
      }
      KeyChangeTok(kc) =>
        // スロットを消費しない。次のスロットの前置（行末なら後置）として保持する。
        // first にも触れない: 転調指示は行頭の小節線の「leading」判定に対して
        // 透明で、[key:+2] | 4 | と | 4 | のスロット構造（cursor.cell 数）は一致する
        pending_keys.push(kc)
    }
  }
  {
    leading,
    slots,
    trailing: bar_pending,
    keys_before,
    trailing_keys: pending_keys,
  }
}

///|
/// 転調チップ列を書き出す（after = 直前セルへの後置チップ）
fn write_key_chips(
  sb : StringBuilder,
  keys : Array[KeyChange],
  key_chip : (KeyChange, Bool) -> String,
  standalone : Bool,
  after : Bool,
) -> Unit {
  for kc in keys {
    let cls = if after { "chord-mod chord-mod--after" } else { "chord-mod" }
    sb.write_string("<span class=\"" + cls + "\">")
    sb.write_string(escape_html(key_chip(kc, standalone)))
    sb.write_string("</span>")
  }
}

///|
/// 転調前ディグリーの薄表示(=V など。空文字なら何も出さない)
fn write_prev_key_html(sb : StringBuilder, label : String) -> Unit {
  if label != "" {
    sb.write_string("<span class=\"chord-prevkey\">")
    sb.write_string(escape_html(label))
    sb.write_string("</span>")
  }
}

///|
/// 1 行分のコード譜をコードスロットのグリッドとして書き出す。
/// スロットはスコア全体で共通の列ラスタ（--chord-cols）に載るため、
/// 行が違っても同じ位置のコード同士が縦に揃う。
/// 小節線（|）はスロット境界の縦線として描画される。
///
/// 転調チップの描画位置: 単独行（スロットなし）= 全幅の .chord-modline、
/// インライン = 次のスロットの前置チップ、行末 = 最後のスロットの後置チップ
/// （段末の予告調号の慣習。スコア末尾の宙吊り指示も消さずに描画される）。
///
/// 不変条件: 実音モードの key_chip は KeyCursor を進める副作用を持つため、
/// チップ → コード（text_of）の文書順で必ず 1 回ずつ評価すること
fn write_line_html(
  sb : StringBuilder,
  line : Line,
  text_of : (ChordNode) -> String,
  key_chip : (KeyChange, Bool) -> String,
  prev_of : (ChordNode) -> String,
  bar_break : () -> Unit,
) -> Unit {
  let ls = line_slots(line.tokens)
  // 転調指示だけの行（スロットなし）は全幅の転調バッジ行として描画する
  if ls.slots.is_empty() && ls.trailing_keys.length() > 0 {
    sb.write_string("<div class=\"chord-modline\">")
    write_key_chips(sb, ls.trailing_keys, key_chip, true, false)
    sb.write_string("</div>")
    return
  }
  let mut cls = "chord-line"
  if ls.leading {
    cls = cls + " chord-line--start-bar"
  }
  if ls.trailing {
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
  let last = ls.slots.length() - 1
  // 行頭 = 新しい小節の始まり(転調前ディグリーの薄表示の解除判定)
  bar_break()
  for i, slot in ls.slots {
    // 行末の転調指示は最後のスロットの後置チップとして描画する
    let write_trailing = fn() {
      if i == last {
        write_key_chips(sb, ls.trailing_keys, key_chip, false, true)
      }
    }
    // 小節線をまたいだら薄表示の対象小節を抜ける
    let slot_bar_before = match slot {
      ChordSlot(_, b) => b
      GroupSlot(_, b) => b
      RepeatSlot(b) => b
      NcSlot(b) => b
      BlankSlot(b) => b
      EmptySlot(b) => b
    }
    if slot_bar_before {
      bar_break()
    }
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
        write_key_chips(sb, ls.keys_before[i], key_chip, false, false)
        sb.write_string(escape_html(text_of(node)))
        write_prev_key_html(sb, prev_of(node))
        write_trailing()
        write_lyric_html(sb, lyric_of())
        sb.write_string("</span>")
      }
      GroupSlot(group_parts, bar_before) => {
        // 1 スロットを複数パートで共有し、等間隔で幅を埋める(八分音符的な拍位置の表現)。
        // 空きパート(_)は空のセルとして間隔だけを占有する(拍位置の表現を保つ)
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord-group" + bar_cls + "\">",
        )
        write_key_chips(sb, ls.keys_before[i], key_chip, false, false)
        // 歌詞断片の割り付け(3 通り):
        // - `-` の分割数がパート数と一致 → 各パートへ配る(コードの実位置に揃う)
        // - 一致しないが 2 分割以上 → 他のスロットと同じ「スロット全幅の等分割」
        //   としてグループの下に描画する(拍分割数はコードと一致しなくてよい)
        // - `-` を含まない → 先頭のパートにまとめて付く(従来どおり)
        let member_lyrics : Array[String?] = []
        let mut slot_lyric : String? = None
        match lyric_of() {
          Some(text) => {
            let parts = text.split("-").map(fn(v) { v.to_owned() }).to_array()
            if parts.length() == group_parts.length() {
              for part in parts {
                member_lyrics.push(Some(part))
              }
            } else if parts.length() > 1 {
              slot_lyric = Some(text)
              for _i in 0..<group_parts.length() {
                member_lyrics.push(None)
              }
            } else {
              member_lyrics.push(Some(text))
              for _i in 1..<group_parts.length() {
                member_lyrics.push(None)
              }
            }
          }
          None =>
            for _i in 0..<group_parts.length() {
              member_lyrics.push(None)
            }
        }
        for j, part in group_parts {
          match part {
            GroupChord(node) => {
              let color_cls = match node.color {
                Some(c) => " chord--" + c.to_string()
                None => ""
              }
              sb.write_string("<span class=\"chord" + color_cls + "\">")
              sb.write_string(escape_html(text_of(node)))
              write_prev_key_html(sb, prev_of(node))
              write_plain_lyric_html(sb, member_lyrics[j])
              sb.write_string("</span>")
            }
            GroupHold => {
              sb.write_string("<span class=\"chord chord-group-hold\">")
              write_plain_lyric_html(sb, member_lyrics[j])
              sb.write_string("</span>")
            }
          }
        }
        // パート数と一致しない拍分割の歌詞はグループ全幅の行として折り返す
        write_lyric_html(sb, slot_lyric)
        write_trailing()
        sb.write_string("</span>")
      }
      RepeatSlot(bar_before) => {
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord chord-repeat" + bar_cls + "\">",
        )
        write_key_chips(sb, ls.keys_before[i], key_chip, false, false)
        sb.write_string("%")
        write_trailing()
        write_lyric_html(sb, lyric_of())
        sb.write_string("</span>")
      }
      NcSlot(bar_before) => {
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord chord-nc" + bar_cls + "\">",
        )
        write_key_chips(sb, ls.keys_before[i], key_chip, false, false)
        sb.write_string("N.C.")
        write_trailing()
        write_lyric_html(sb, lyric_of())
        sb.write_string("</span>")
      }
      BlankSlot(bar_before) => {
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord-cell--blank" + bar_cls + "\">",
        )
        write_key_chips(sb, ls.keys_before[i], key_chip, false, false)
        write_trailing()
        write_lyric_html(sb, lyric_of())
        sb.write_string("</span>")
      }
      EmptySlot(bar_before) => {
        let bar_cls = if bar_before { " chord-cell--bar-before" } else { "" }
        sb.write_string(
          "<span class=\"chord-cell chord-cell--empty" + bar_cls + "\">",
        )
        write_key_chips(sb, ls.keys_before[i], key_chip, false, false)
        write_trailing()
        sb.write_string("</span>")
      }
    }
  }
  // 行末 = 小節の終わり(転調バッジ行・行末チップの直後は未消費なので次の行へ持ち越す)
  bar_break()
  sb.write_string("</div>")
}

///|
/// 歌詞断片を 1 つの歌詞としてそのまま書き出す（分割しない。None は何も出さない）。
/// グループの各パートに配られた歌詞と、パート数が合わずまとめて先頭に付く
/// フォールバック（従来挙動）はこちらを使う
fn write_plain_lyric_html(sb : StringBuilder, frag : String?) -> Unit {
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
/// 歌詞断片をコードの下に書き出す（None は何も出さない）。
/// 断片に `-` が含まれる場合は**拍分割**: スロットを等分した等幅カラムに
/// 各パートを置く（コード側のグループ `-` と同じ概念。`_-あいあい` なら
/// 2 等分の後半 = 4/4 の 3 拍目から歌詞が始まる。空きパートは `_` か空で書く）
fn write_lyric_html(sb : StringBuilder, frag : String?) -> Unit {
  match frag {
    Some(text) => {
      let parts = text.split("-").map(fn(v) { v.to_owned() }).to_array()
      if parts.length() > 1 {
        sb.write_string("<span class=\"chord-lyric chord-lyric--split\">")
        for part in parts {
          // 空・空白のみ（_ 由来）のパートは空き拍のカラムとして幅だけ占有する
          sb.write_string("<span class=\"chord-lyric-beat\">")
          sb.write_string(escape_html(part))
          sb.write_string("</span>")
        }
        sb.write_string("</span>")
      } else {
        write_plain_lyric_html(sb, frag)
      }
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
/// （転調指示はスロットを消費しないため列数に影響しない）
fn score_slot_cols(ast : ScoreAST) -> Int {
  let mut cols = 1
  for line in ast.lines {
    let ls = line_slots(line.tokens)
    if ls.slots.length() > cols {
      cols = ls.slots.length()
    }
  }
  cols
}

///|
/// ディグリータブ用の転調チップのラベル。キー非依存タブのためソース忠実形。
/// 単独行は "key +1" / "key F"、インライン（セル上部のチップ）は小節上の
/// 限られた幅に収めるコンパクト形 "+1" / "F"（b は表示層の流儀で ♭ にする）
fn key_change_degree_label(kc : KeyChange, standalone : Bool) -> String {
  let value = match kc {
    RelativeKey(_) => kc.to_source_text()
    AbsoluteKey(k) => key_display_label(k)
  }
  if standalone {
    "key " + value
  } else {
    value
  }
}

///|
/// 旧キー上のディグリー表記（ピッチクラス 0-11 → ローマ数字）。
/// pc 6 は正準 12 キー表の F#（シャープ側）の選択に合わせて #IV で綴る
fn prev_degree_label(pc : Int) -> String {
  [
    "I", "♭II", "II", "♭III", "III", "IV", "#IV", "V", "♭VI", "VI", "♭VII",
    "VII",
  ][(pc % 12 + 12) % 12]
}

///|
/// ディグリータブ用の「転調チップ + 転調前ディグリーの薄表示」クロージャ一式。
/// 転調チップが付いた小節（次の小節線まで）のコードに、転調前のキーで読んだ
/// ディグリー（ピボットの読み）を =V のように薄く添える。
/// キープルダウンの δ は新旧キーを同じだけ動かすので、この関係は移調不変
/// （宣言キー基準の計算でよい）。
/// 返り値: (key_chip, prev_of, bar_break)。write_line_html が
/// 「小節境界 → チップ → コード」の文書順で呼ぶことが不変条件
fn make_degree_chips(
  declared : String,
) -> ((KeyChange, Bool) -> String, (ChordNode) -> String, () -> Unit) {
  let mut cur_pc = match parse_key_name(declared) {
    Some(k) => key_pitch_class(k)
    None => 0 // C
  }
  let mut old_pc : Int? = None // Some = 転調直後の小節内（転調前のキーの pc）
  let mut used = false // この小節で薄表示を出したか（出ていれば次の小節境界で解除）
  let key_chip = fn(kc : KeyChange, standalone : Bool) -> String {
    // 同じ小節に転調指示が連続する場合は、最初の指示の前のキーを「転調前」に保つ
    match old_pc {
      Some(_) =>
        if used {
          old_pc = Some(cur_pc)
          used = false
        }
      None => {
        old_pc = Some(cur_pc)
        used = false
      }
    }
    cur_pc = apply_key_change_pc(cur_pc, 0, kc)
    key_change_degree_label(kc, standalone)
  }
  let prev_of = fn(node : ChordNode) -> String {
    match old_pc {
      Some(op) => {
        used = true
        let acc = match node.accidental {
          Some(Sharp) => 1
          Some(Flat) => -1
          None => 0
        }
        let rel = ((degree_interval(node.degree) + acc + cur_pc - op) % 12 + 12) %
          12
        "=" + prev_degree_label(rel)
      }
      None => ""
    }
  }
  let bar_break = fn() -> Unit {
    if used {
      old_pc = None
      used = false
    }
  }
  (key_chip, prev_of, bar_break)
}

///|
/// フロントマターで宣言された初期キー（宣言時のみ Some。既定値 C では出さない）
fn declared_key(ast : ScoreAST) -> String? {
  match ast.meta {
    Some(meta) => meta.key
    None => None
  }
}

///|
/// 譜面冒頭の初期キーチップ（転調の単独行と同じ全幅 .chord-modline）。
/// 転調がなくても、フロントマターでキーを宣言した曲は冒頭でキーがわかる
fn write_initial_key_html(sb : StringBuilder, label : String?) -> Unit {
  match label {
    Some(l) =>
      sb.write_string(
        "<div class=\"chord-modline\"><span class=\"chord-mod\">" +
        escape_html(l) +
        "</span></div>",
      )
    None => ()
  }
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
/// ScoreAST を HTML 文字列に変換する（表示テキスト関数と転調チップ関数を指定）。
/// 行（とその中のチップ・コード）は文書順に 1 回ずつ評価される
fn render_score_html(
  ast : ScoreAST,
  text_of : (ChordNode) -> String,
  key_chip : (KeyChange, Bool) -> String,
  prev_of : (ChordNode) -> String,
  bar_break : () -> Unit,
  initial_key : String?,
) -> String {
  let cols = score_slot_cols(ast)
  let sb = StringBuilder::new()
  sb.write_string(
    "<div class=\"chord-score\" style=\"--chord-cols:" +
    cols.to_string() +
    "\">",
  )
  write_initial_key_html(sb, initial_key)
  let mut si = 0
  for line in ast.lines {
    while si < ast.sections.length() &&
          ast.sections[si].line_number < line.line_number {
      write_section_html(sb, ast.sections[si])
      si = si + 1
    }
    write_line_html(sb, line, text_of, key_chip, prev_of, bar_break)
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
  let (key_chip, prev_of, bar_break) = make_degree_chips(ast.key_or_default())
  // ディグリータブの初期キーチップは宣言の綴りに忠実（"key E♭" 形式）
  let initial_key = match declared_key(ast) {
    Some(k) => Some("key " + key_display_label(k))
    None => None
  }
  render_score_html(
    ast, chord_display_text, key_chip, prev_of, bar_break, initial_key,
  )
}

///|
/// 実音表示のスコア HTML（転調の文書順 fold 込み）。
/// selected はキープルダウンの選択キー = 初期キーの差し替え。
/// key_chip が KeyCursor を進める副作用を持つため、write_line_html の
/// 「チップ → コードの文書順で 1 回ずつ評価する」不変条件に依存している
fn render_notes_score_html(score : ScoreAST, selected : KeyInfo) -> String {
  let declared = match parse_key_name(score.key_or_default()) {
    Some(k) => k
    None => { letter_idx: 0, alter: 0 } // C
  }
  let cursor = KeyCursor::make(selected, declared)
  // 実音タブの初期キーチップは実効キー = プルダウンの選択キー（移調に追従）
  let initial_key = match declared_key(score) {
    Some(_) => Some("Key " + key_display_label(key_info_name(selected)))
    None => None
  }
  render_score_html(
    score,
    fn(node) { chord_note_text(node, cursor.current) },
    fn(kc, standalone) {
      cursor.apply(kc)
      let name = key_display_label(key_info_name(cursor.current))
      if standalone {
        // 単独行は転調幅を併記（相対のみ。絶対はキー名だけ）
        match kc {
          RelativeKey(_) => "Key " + name + " (" + kc.to_source_text() + ")"
          AbsoluteKey(_) => "Key " + name
        }
      } else {
        // インラインは幅優先でキー名のみ
        name
      }
    },
    // 転調前ディグリーの薄表示はディグリータブ専用(実音タブでは出さない)
    fn(_node) { "" },
    fn() {  },
    initial_key,
  )
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
  // ディグリー表示のチップ・転調前ディグリー状態(描画される行だけで fold する)
  let (key_chip, prev_of, bar_break) = make_degree_chips(
    result.score.key_or_default(),
  )
  let sb = StringBuilder::new()
  sb.write_string(
    "<div class=\"chord-score\" style=\"--chord-cols:" +
    cols.to_string() +
    "\">",
  )
  // エラー埋め込み表示でも、宣言キーがあれば冒頭チップは出す（ディグリー形式）
  let initial_key = match declared_key(result.score) {
    Some(k) => Some("key " + key_display_label(k))
    None => None
  }
  write_initial_key_html(sb, initial_key)
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
      Some(line) =>
        write_line_html(
          sb, line, chord_display_text, key_chip, prev_of, bar_break,
        )
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
/// 単一のコード記号をインライン表示用 HTML にする。
/// ホスト Markdown のインラインコード譜記法（markdown.mbt フォークの `:2m7:`）が
/// 使う想定で、表示はディグリーのみ（タブ・移調・再生は持たない）。
/// 文法はブロックのコード記号と同一（アクシデンタル・クオリティ・テンション・
/// スラッシュベース・@色）。単一のコード記号としてパースできない場合は
/// 空文字列を返し、呼び出し側が元テキストのまま表示するようフォールバックする。
pub fn inline_chord_html(token : String) -> String {
  match parse_chord(token) {
    Ok(node) => {
      let color_cls = match node.color {
        Some(c) => " chord--" + c.to_string()
        None => ""
      }
      "<span class=\"chord-inline" +
      color_cls +
      "\">" +
      escape_html(chord_display_text(node)) +
      "</span>"
    }
    Err(_) => ""
  }
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
    Some(key_info) => render_notes_score_html(result.score, key_info)
    None => render_html(result.score)
  }
}
