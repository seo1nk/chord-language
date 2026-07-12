///|
/// パース結果（部分 AST + エラー列）。
/// fail-fast はしない: エラー行は score から除外され errors に集まり、
/// 正しい行は score.lines に残る（ライブプレビュー用途のエラー耐性設計）。
pub struct ParseResult {
  score : ScoreAST
  errors : Array[ParseError]
}

///|
/// 入力文字列をパースして ParseResult を返す。
///
/// - フロントマター（ブロック先頭の `--- key: G ---` 等）を解釈する
/// - 行ごとにトークンを解析し、エラーのある行は score から除外して errors に記録する
/// - 行番号は元ソース基準（1-indexed）、position は行内の 0-indexed 文字位置
pub fn parse(input : String) -> ParseResult {
  let all_lines = split_lines(input)
  let (meta, fm_errors, body_start) = parse_frontmatter(all_lines)
  let errors : Array[ParseError] = []
  for e in fm_errors {
    errors.push(e)
  }
  let lines : Array[Line] = []
  let sections : Array[SectionLabel] = []
  for idx in body_start..<all_lines.length() {
    let line_number = idx + 1 // 1-indexed
    let raw = all_lines[idx]
    let trimmed = raw.trim().to_owned()

    // 歌詞行: > で始まる行は直前のコード行への歌詞割り当て
    if trimmed.has_prefix(">") {
      let fragments = parse_lyric_fragments(trimmed)
      // 直前の「ソース上の前の行」がパース済みのコード行であること
      let attached = if lines.length() > 0 &&
        lines[lines.length() - 1].line_number == line_number - 1 {
        let target = lines[lines.length() - 1]
        let slot_count = count_lyric_slots(target.tokens)
        if fragments.length() > slot_count {
          errors.push(
            too_many_lyric_fragments_error(
              fragments.length(),
              slot_count,
              line_number,
            ),
          )
        }
        // 超過分は切り捨てて先頭から割り当てる（コード行の描画は維持）
        let assigned : Array[String?] = []
        for i in 0..<slot_count {
          if i < fragments.length() {
            assigned.push(fragments[i])
          } else {
            assigned.push(None)
          }
        }
        target.lyrics = assigned
        true
      } else {
        false
      }
      if !attached {
        errors.push(orphan_lyric_line_error(line_number))
      }
      continue
    }

    // セクションラベル: [名前] の単独行。
    // ただし中身が key（小文字）+ コロンで始まる行は転調指示（[key: 値]）で
    // あり、セクションにはしない（下のトークン化パスで KeyTok として解釈する）
    let trimmed_chars = trimmed.to_array()
    let is_key_change_line = trimmed.has_prefix("[") &&
      is_key_change_inner(trimmed_chars, 1, trimmed_chars.length())
    if !is_key_change_line &&
      trimmed.length() >= 2 &&
      trimmed.has_prefix("[") &&
      trimmed.has_suffix("]") {
      let name = trimmed
        .unsafe_substring(start=1, end=trimmed.length() - 1)
        .trim()
        .to_owned()
      sections.push({ line_number, name })
      continue
    }
    let pos_tokens = tokenize_line(all_lines[idx])
    if pos_tokens.length() == 0 {
      continue
    }
    let tokens : Array[Token] = []
    let mut line_ok = true
    for pt in pos_tokens {
      match pt.kind {
        BarTok => tokens.push(BarLine)
        RepeatTok => tokens.push(Repeat)
        BlankTok => tokens.push(EmptyBeat)
        KeyTok =>
          // 転調指示。プレフィックス（[key ... :）に一致したトークンは、
          // 値が不正・未クローズでも必ず InvalidKeyChange として報告する
          match parse_key_change_token(pt.text) {
            Some(kc) => tokens.push(KeyChangeTok(kc))
            None => {
              errors.push(
                invalid_key_change_error(pt.text, 0)
                .shift_position(pt.col)
                .with_line(line_number),
              )
              line_ok = false
            }
          }
        ChordTok =>
          if !parse_chord_token(pt, line_number, tokens, errors) {
            line_ok = false
          }
      }
    }
    if line_ok {
      lines.push({ line_number, tokens, lyrics: [] })
    }
  }
  { score: { meta, sections, lines }, errors }
}

///|
/// コードトークン（`-` グループ・NC 含む）を解析して tokens に追加する。
/// エラーは行番号・行内位置つきで errors に積む。
/// 返り値: トークンが有効だったか（false なら呼び出し側が行を無効化する）
fn parse_chord_token(
  pt : PosToken,
  line_number : Int,
  tokens : Array[Token],
  errors : Array[ParseError],
) -> Bool {
  // - で連結されたグループ（1 スロット複数コード）を分割
  let (parts, offsets) = split_group_parts(pt.text)
  // 全パートが空（"---" など区切り文字だけのトークン）は 1 つの
  // UnrecognizedToken として報告する
  let mut all_empty = true
  for part in parts {
    if !part.is_empty() {
      all_empty = false
      break
    }
  }
  if all_empty {
    errors.push(
      unrecognized_token_error(pt.text, 0)
      .shift_position(pt.col)
      .with_line(line_number),
    )
    return false
  }
  if parts.length() == 1 && (pt.text == "NC" || pt.text == "N.C.") {
    // NC / N.C.（コードなし）
    tokens.push(NoChord)
    return true
  }
  if parts.length() == 1 {
    match parse_chord(pt.text) {
      Ok(node) => {
        tokens.push(Chord(node))
        return true
      }
      Err(e) => {
        // トークン内位置 → 行内位置へシフトし、行番号を付与
        errors.push(e.shift_position(pt.col).with_line(line_number))
        return false
      }
    }
  }
  // グループに分割する前に、トークン全体を単一コードとして試す。
  // ハーフディミニッシュの -5 表記(2m7-5)をグループ 2m7 + 5 より優先する
  // ため。-5 は m7 の直後のみ受理されるので、度数のみの 2-5 などは単一
  // コードとして成立せず、従来どおりグループになる
  match parse_chord(pt.text) {
    Ok(node) => {
      tokens.push(Chord(node))
      return true
    }
    Err(_) => ()
  }
  let chords : Array[ChordNode] = []
  let mut ok = true
  for i, part in parts {
    if part.is_empty() {
      errors.push(
        unrecognized_token_error(pt.text, 0)
        .shift_position(pt.col + offsets[i])
        .with_line(line_number),
      )
      ok = false
    } else {
      match parse_chord(part) {
        Ok(node) => chords.push(node)
        Err(e) => {
          errors.push(
            e.shift_position(pt.col + offsets[i]).with_line(line_number),
          )
          ok = false
        }
      }
    }
  }
  if ok {
    tokens.push(ChordGroup(chords))
  }
  ok
}

///|
/// 転調指示トークン（[key: 値]）の値を解析する。
/// - 相対値: ("+" | "-") + 半音数 1〜11（0 と 12 以上は不正）
/// - 絶対キー: フロントマターの key と同一文法（A〜G + 任意の #/b）
/// - 空白は [・key・:・値の前後で許容する（[ key : +2 ] も可）
/// 未クローズ・値の欠落・不正値は None（呼び出し側が InvalidKeyChange にする）
fn parse_key_change_token(text : String) -> KeyChange? {
  let chars = text.to_array()
  let len = chars.length()
  // [ ... ] の形であること（未クローズは不正）
  if len < 2 || chars[0] != '[' || chars[len - 1] != ']' {
    return None
  }
  let end = len - 1
  let mut i = 1
  while i < end && is_whitespace(chars[i]) {
    i = i + 1
  }
  // プレフィックス key 空白* :（レキサで判定済みだが、この関数単体でも成立させる）
  if i + 3 > end ||
    chars[i] != 'k' ||
    chars[i + 1] != 'e' ||
    chars[i + 2] != 'y' {
    return None
  }
  i = i + 3
  while i < end && is_whitespace(chars[i]) {
    i = i + 1
  }
  if i >= end || chars[i] != ':' {
    return None
  }
  i = i + 1
  // 値（前後の空白を除く）
  let mut vend = end
  while i < vend && is_whitespace(chars[i]) {
    i = i + 1
  }
  while vend > i && is_whitespace(chars[vend - 1]) {
    vend = vend - 1
  }
  if i >= vend {
    return None // 値の欠落（[key:]）
  }
  let sb = StringBuilder::new()
  for k in i..<vend {
    sb.write_char(chars[k])
  }
  let value = sb.to_string()
  if chars[i] == '+' || chars[i] == '-' {
    // 相対値: 符号の後は数字のみ
    if vend - i < 2 {
      return None
    }
    let mut n = 0
    for k in (i + 1)..<vend {
      match chars[k] {
        '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
          n = n * 10 + (chars[k].to_int() - 48)
        _ => return None
      }
      if n > 11 {
        return None
      }
    }
    if n < 1 {
      return None
    }
    if chars[i] == '-' {
      Some(RelativeKey(-n))
    } else {
      Some(RelativeKey(n))
    }
  } else if is_valid_key(value) {
    Some(AbsoluteKey(value))
  } else {
    None
  }
}

///|
/// 歌詞行（> ...）を断片に分割する。
/// - 空白区切り。断片中の `_` は表示上のスペース、`_` 単独は「歌詞なし」
fn parse_lyric_fragments(trimmed : String) -> Array[String?] {
  // 先頭の > を除去
  let body = trimmed.unsafe_substring(start=1, end=trimmed.length())
  let fragments : Array[String?] = []
  let sb = StringBuilder::new()
  let flush = fn() {
    if !sb.is_empty() {
      let frag = sb.to_string()
      sb.reset()
      if frag == "_" {
        fragments.push(None)
      } else {
        fragments.push(Some(frag.replace_all(old="_", new=" ")))
      }
    }
  }
  for c in body {
    if is_whitespace(c) {
      flush()
    } else {
      sb.write_char(c)
    }
  }
  flush()
  fragments
}

///|
/// 歌詞を割り当てられるスロット数（Chord / ChordGroup / Repeat の数）
fn count_lyric_slots(tokens : Array[Token]) -> Int {
  let mut n = 0
  for token in tokens {
    match token {
      Chord(_) | ChordGroup(_) | Repeat | NoChord | EmptyBeat => n = n + 1
      BarLine | KeyChangeTok(_) => () // 転調指示はスロットを消費しない
    }
  }
  n
}

///|
/// グループ区切り（-）でトークンを分割する。括弧の内側では分割しない。
/// 返り値: (パート列, 各パートのトークン内開始オフセット)
fn split_group_parts(text : String) -> (Array[String], Array[Int]) {
  let parts : Array[String] = []
  let offsets : Array[Int] = []
  let chars = text.to_array()
  let sb = StringBuilder::new()
  let mut depth = 0
  let mut start = 0
  for i, c in chars {
    if depth == 0 && c == '-' {
      parts.push(sb.to_string())
      offsets.push(start)
      sb.reset()
      start = i + 1
    } else {
      if c == '(' {
        depth = depth + 1
      }
      if c == ')' && depth > 0 {
        depth = depth - 1
      }
      sb.write_char(c)
    }
  }
  parts.push(sb.to_string())
  offsets.push(start)
  (parts, offsets)
}

///|
/// ScoreASTを文字列に変換（デバッグ用）
pub fn ScoreAST::to_string(self : ScoreAST) -> String {
  let line_strs = self.lines.map(fn(line) { line_to_string(line) })
  "ScoreAST {\n" + line_strs.map(fn(s) { "  " + s }).join("\n") + "\n}"
}

///|
/// Lineを文字列に変換（デバッグ用）
fn line_to_string(line : Line) -> String {
  let token_strs = line.tokens.map(token_to_string)
  "Line \{line.line_number} [" + token_strs.join(", ") + "]"
}

///|
/// Tokenを文字列に変換（デバッグ用）
fn token_to_string(token : Token) -> String {
  match token {
    Chord(node) => "Chord(" + chord_node_to_string(node) + ")"
    ChordGroup(nodes) =>
      "ChordGroup(" + nodes.map(chord_node_to_string).join("-") + ")"
    BarLine => "BarLine"
    Repeat => "Repeat"
    NoChord => "NoChord"
    EmptyBeat => "EmptyBeat"
    KeyChangeTok(kc) => "KeyChange(" + kc.to_source_text() + ")"
  }
}

///|
/// ChordNodeを文字列に変換（デバッグ用、色アノテーション込み）
fn chord_node_to_string(node : ChordNode) -> String {
  let color_str = match node.color {
    Some(c) => "@" + c.to_string()
    None => ""
  }
  chord_source_text(node) + color_str
}

///|
/// ChordNodeをDSLソース表記のテキストに変換（色アノテーションを除く。表示用）
fn chord_source_text(node : ChordNode) -> String {
  let acc = match node.accidental {
    Some(Sharp) => "s"
    Some(Flat) => "b"
    None => ""
  }
  let deg = node.degree.to_string()
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
    Some(FlatFive) => "b5"
    Some(Sus(d)) => "sus" + d.to_string()
    None => ""
  }
  let opts = if node.options.length() > 0 {
    "(" + node.options.map(option_to_string).join(",") + ")"
  } else {
    ""
  }
  let bass_str = match node.bass {
    Some(b) => {
      let b_acc = match b.accidental {
        Some(Sharp) => "s"
        Some(Flat) => "b"
        None => ""
      }
      "/" + b_acc + b.degree.to_string()
    }
    None => ""
  }
  acc + deg + qual + sev + alt + opts + bass_str
}

///|
/// ChordOptionを文字列に変換（デバッグ用）
fn option_to_string(opt : ChordOption) -> String {
  match opt {
    TensionOpt(FlatNine) => "b9"
    TensionOpt(Nine) => "9"
    TensionOpt(SharpNine) => "s9"
    TensionOpt(Eleven) => "11"
    TensionOpt(SharpEleven) => "s11"
    TensionOpt(FlatThirteen) => "b13"
    TensionOpt(Thirteen) => "13"
    AlterationOpt(FlatFive) => "b5"
    AlterationOpt(Sus(d)) => "sus" + d.to_string()
  }
}

///|
/// ScoreASTをJSON文字列に変換（仕様書の JSON 形状。エスケープは Json::stringify に委譲）
pub fn ScoreAST::to_json(self : ScoreAST) -> String {
  self.to_json_value().stringify(indent=2)
}

///|
/// ScoreASTを Json 値に変換
pub fn ScoreAST::to_json_value(self : ScoreAST) -> Json {
  let obj : Map[String, Json] = {}
  obj["type"] = Json::string("ScoreBlock")
  match self.meta {
    Some(meta) => {
      let m : Map[String, Json] = {}
      match meta.key {
        Some(k) => m["key"] = Json::string(k)
        None => ()
      }
      match meta.bpm {
        Some(t) => m["bpm"] = Json::number(t.to_double())
        None => ()
      }
      match meta.time {
        Some(t) => m["time"] = Json::string(t)
        None => ()
      }
      obj["meta"] = Json::object(m)
    }
    None => ()
  }
  if self.sections.length() > 0 {
    obj["sections"] = Json::array(
      self.sections.map(fn(sec) {
        let so : Map[String, Json] = {}
        so["line"] = Json::number(sec.line_number.to_double())
        so["name"] = Json::string(sec.name)
        Json::object(so)
      }),
    )
  }
  obj["lines"] = Json::array(self.lines.map(line_to_json_value))
  Json::object(obj)
}

///|
fn line_to_json_value(line : Line) -> Json {
  let obj : Map[String, Json] = {}
  obj["line"] = Json::number(line.line_number.to_double())
  obj["tokens"] = Json::array(line.tokens.map(token_to_json_value))
  if line.lyrics.length() > 0 {
    obj["lyrics"] = Json::array(
      line.lyrics.map(fn(frag) {
        match frag {
          Some(t) => Json::string(t)
          None => Json::null()
        }
      }),
    )
  }
  Json::object(obj)
}

///|
/// `{"type": name}` だけの JSON オブジェクト（構造を持たないトークン用）
fn type_only_json(name : String) -> Json {
  let obj : Map[String, Json] = {}
  obj["type"] = Json::string(name)
  Json::object(obj)
}

///|
fn token_to_json_value(token : Token) -> Json {
  match token {
    Chord(node) => {
      let obj : Map[String, Json] = {}
      obj["type"] = Json::string("Chord")
      obj["chord"] = chord_node_to_json_value(node)
      Json::object(obj)
    }
    ChordGroup(nodes) => {
      let obj : Map[String, Json] = {}
      obj["type"] = Json::string("ChordGroup")
      obj["chords"] = Json::array(nodes.map(chord_node_to_json_value))
      Json::object(obj)
    }
    BarLine => type_only_json("BarLine")
    Repeat => type_only_json("Repeat")
    NoChord => type_only_json("NoChord")
    EmptyBeat => type_only_json("EmptyBeat")
    KeyChangeTok(kc) => {
      let obj : Map[String, Json] = {}
      obj["type"] = Json::string("KeyChange")
      let change : Map[String, Json] = {}
      match kc {
        RelativeKey(n) => {
          change["type"] = Json::string("relative")
          change["semitones"] = Json::number(n.to_double())
        }
        AbsoluteKey(k) => {
          change["type"] = Json::string("absolute")
          change["key"] = Json::string(k)
        }
      }
      obj["change"] = Json::object(change)
      Json::object(obj)
    }
  }
}

///|
fn chord_node_to_json_value(node : ChordNode) -> Json {
  let obj : Map[String, Json] = {}

  // accidental
  match node.accidental {
    Some(Sharp) => obj["accidental"] = Json::string("s")
    Some(Flat) => obj["accidental"] = Json::string("b")
    None => ()
  }

  // degree
  obj["degree"] = Json::string(node.degree.to_string())

  // quality
  match node.quality {
    Some(Minor) => obj["quality"] = Json::string("m")
    Some(Diminish) => obj["quality"] = Json::string("dim")
    Some(Augment) => obj["quality"] = Json::string("aug")
    Some(Quartal) => obj["quality"] = Json::string("q")
    None => ()
  }

  // seventh
  match node.seventh {
    Some(Seventh) => obj["seventh"] = { "type": "seventh", "value": "7" }
    Some(MajorSeventh) => obj["seventh"] = { "type": "seventh", "value": "M7" }
    Some(Sixth) => obj["seventh"] = { "type": "seventh", "value": "6" }
    Some(Add(d)) =>
      obj["seventh"] = { "type": "add", "degree": Json::string(d.to_string()) }
    None => ()
  }

  // alteration
  match node.alteration {
    Some(FlatFive) => obj["alteration"] = { "type": "b5" }
    Some(Sus(d)) =>
      obj["alteration"] = {
        "type": "sus",
        "degree": Json::string(d.to_string()),
      }
    None => ()
  }

  // options
  if node.options.length() > 0 {
    obj["options"] = Json::array(node.options.map(option_to_json_value))
  }

  // bass
  match node.bass {
    Some(b) => obj["bass"] = bass_note_to_json_value(b)
    None => ()
  }

  // color
  match node.color {
    Some(c) => obj["color"] = Json::string(c.to_string())
    None => ()
  }
  Json::object(obj)
}

///|
fn option_to_json_value(opt : ChordOption) -> Json {
  match opt {
    TensionOpt(FlatNine) => { "type": "b9" }
    TensionOpt(Nine) => { "type": "9" }
    TensionOpt(SharpNine) => { "type": "s9" }
    TensionOpt(Eleven) => { "type": "11" }
    TensionOpt(SharpEleven) => { "type": "s11" }
    TensionOpt(FlatThirteen) => { "type": "b13" }
    TensionOpt(Thirteen) => { "type": "13" }
    AlterationOpt(FlatFive) => { "type": "b5" }
    AlterationOpt(Sus(d)) =>
      { "type": "sus", "degree": Json::string(d.to_string()) }
  }
}

///|
fn bass_note_to_json_value(bass : BassNote) -> Json {
  let obj : Map[String, Json] = {}
  match bass.accidental {
    Some(Sharp) => obj["accidental"] = Json::string("s")
    Some(Flat) => obj["accidental"] = Json::string("b")
    None => ()
  }
  obj["degree"] = Json::string(bass.degree.to_string())
  Json::object(obj)
}
