/// パース状態を保持する構造体
struct ParserState {
  input: String
  pos: Int
  length: Int
}

/// ParserStateのコンストラクタ
fn ParserState::new(input: String) -> ParserState {
  { input, pos: 0, length: input.length() }
}

/// 現在位置の文字を取得（範囲外ならNone）
fn ParserState::current_char(self: ParserState) -> Option[Char] {
  if self.pos < self.length {
    Some(self.input[self.pos])
  } else {
    None
  }
}

/// 現在位置からn文字先を取得
fn ParserState::peek(self: ParserState, n: Int) -> Option[Char] {
  let target_pos = self.pos + n
  if target_pos < self.length {
    Some(self.input[target_pos])
  } else {
    None
  }
}

/// 位置を進める
fn ParserState::advance(self: ParserState, n: Int) -> ParserState {
  { input: self.input, pos: self.pos + n, length: self.length }
}

/// 現在位置から指定文字数の文字列を取得
fn ParserState::substring(self: ParserState, length: Int) -> String {
  self.input.substring(self.pos, self.pos + length)
}

/// 残りの文字列を取得
fn ParserState::remaining(self: ParserState) -> String {
  self.input.substring(self.pos, self.length)
}

/// アクシデンタルをパース
fn parse_accidental(state: ParserState) -> (ParserState, Option[Accidental]) {
  match state.current_char() {
    Some('s') => (state.advance(1), Some(Sharp))
    Some('b') => (state.advance(1), Some(Flat))
    _ => (state, None)
  }
}

/// ディグリーをパース
fn parse_degree(state: ParserState, token: String) -> Result[(ParserState, Degree), ParseError] {
  match state.current_char() {
    Some(c) => {
      match Degree::from_char(c) {
        Some(degree) => Ok((state.advance(1), degree))
        None => Err(invalid_degree_error(c.to_string(), token))
      }
    }
    None => Err(invalid_degree_error("", token))
  }
}

/// クオリティをパース
fn parse_quality(state: ParserState) -> (ParserState, Option[Quality]) {
  // "dim" (3文字) をチェック
  if state.pos + 3 <= state.length && state.substring(3) == "dim" {
    return (state.advance(3), Some(Diminish))
  }
  
  // "aug" (3文字) をチェック
  if state.pos + 3 <= state.length && state.substring(3) == "aug" {
    return (state.advance(3), Some(Augment))
  }
  
  // "m" (1文字) をチェック
  match state.current_char() {
    Some('m') => (state.advance(1), Some(Minor))
    _ => (state, None)
  }
}

/// セブンスをパース（優先順位: M7 → 7 → 6 → add系）
fn parse_seventh(state: ParserState, token: String) -> Result[(ParserState, Option[Seventh]), ParseError] {
  // M7 をチェック（2文字）
  if state.pos + 2 <= state.length && state.substring(2) == "M7" {
    return Ok((state.advance(2), Some(MajorSeventh)))
  }
  
  // 7 をチェック（1文字）
  match state.current_char() {
    Some('7') => return Ok((state.advance(1), Some(Seventh)))
    Some('6') => return Ok((state.advance(1), Some(Sixth)))
    _ => {}
  }
  
  // add系をチェック
  if state.pos + 3 <= state.length && state.substring(3) == "add" {
    let after_add = state.advance(3)
    // addの後のディグリーを取得
    let remaining = after_add.remaining()
    
    // 2桁の数字をチェック（11, 13）
    if remaining.length() >= 2 {
      let two_chars = remaining.substring(0, 2)
      match AddDegree::from_string(two_chars) {
        Some(degree) => return Ok((after_add.advance(2), Some(Add(degree))))
        None => {}
      }
    }
    
    // 1桁の数字をチェック（2, 4, 6, 9）
    if remaining.length() >= 1 {
      let one_char = remaining.substring(0, 1)
      match AddDegree::from_string(one_char) {
        Some(degree) => return Ok((after_add.advance(1), Some(Add(degree))))
        None => return Err(invalid_seventh_error("add" + one_char, token))
      }
    }
    
    return Err(invalid_seventh_error("add", token))
  }
  
  Ok((state, None))
}

/// オルタレーション（括弧外）をパース
fn parse_alteration(state: ParserState, token: String) -> Result[(ParserState, Option[Alteration]), ParseError] {
  // b5 をチェック
  if state.pos + 2 <= state.length && state.substring(2) == "b5" {
    return Ok((state.advance(2), Some(FlatFive)))
  }
  
  // sus をチェック
  if state.pos + 3 <= state.length && state.substring(3) == "sus" {
    let after_sus = state.advance(3)
    match after_sus.current_char() {
      Some(c) => {
        match Degree::from_char(c) {
          Some(degree) => {
            // sus度数の妥当性チェック（2, 4, 6のみ）
            match degree {
              D2 | D4 | D6 => Ok((after_sus.advance(1), Some(Sus(degree))))
              _ => Err(invalid_sus_degree_error(c.to_string(), token))
            }
          }
          None => Err(invalid_sus_degree_error(c.to_string(), token))
        }
      }
      None => Err(invalid_sus_degree_error("", token))
    }
  } else {
    Ok((state, None))
  }
}

/// テンションをパース
fn parse_tension(s: String, token: String) -> Result[Tension, ParseError] {
  match s {
    "b9" => Ok(FlatNine)
    "9" => Ok(Nine)
    "s9" => Ok(SharpNine)
    "11" => Ok(Eleven)
    "s11" => Ok(SharpEleven)
    "b13" => Ok(FlatThirteen)
    "13" => Ok(Thirteen)
    _ => Err(invalid_tension_error(s, token))
  }
}

/// 括弧内オプションの1つをパース
fn parse_single_option(s: String, token: String) -> Result[ChordOption, ParseError] {
  let trimmed = s.trim()
  
  // b5 をチェック
  if trimmed == "b5" {
    return Ok(AlterationOpt(FlatFive))
  }
  
  // sus をチェック
  if trimmed.starts_with("sus") && trimmed.length() == 4 {
    let degree_char = trimmed[3]
    match Degree::from_char(degree_char) {
      Some(degree) => {
        match degree {
          D2 | D4 | D6 => Ok(AlterationOpt(Sus(degree)))
          _ => Err(invalid_sus_degree_error(degree_char.to_string(), token))
        }
      }
      None => Err(invalid_option_error(trimmed, token))
    }
  } else {
    // テンションとしてパース
    match parse_tension(trimmed, token) {
      Ok(tension) => Ok(TensionOpt(tension))
      Err(e) => Err(e)
    }
  }
}

/// 括弧内オプションをパース
fn parse_options(content: String, token: String) -> Result[Array[ChordOption], ParseError] {
  // 空の括弧チェック
  if content.trim().is_empty() {
    return Err(empty_parentheses_error(token))
  }
  
  let parts = content.split(',')
  let options: Array[ChordOption] = []
  
  // カンマの不正使用チェック
  for part in parts {
    if part.trim().is_empty() {
      return Err(invalid_comma_usage_error(token))
    }
  }
  
  // 各オプションをパース
  for part in parts {
    match parse_single_option(part, token) {
      Ok(option) => options.push(option)
      Err(e) => return Err(e)
    }
  }
  
  Ok(options)
}

/// 括弧内オプションをパース（括弧を含む）
fn parse_parenthesized_options(state: ParserState, token: String) -> Result[(ParserState, Array[ChordOption]), ParseError] {
  match state.current_char() {
    Some('(') => {
      // 閉じ括弧を探す
      let remaining = state.remaining()
      match remaining.index_of(')') {
        Some(close_idx) => {
          // 括弧内の内容を取得
          let content = remaining.substring(1, close_idx)
          match parse_options(content, token) {
            Ok(options) => Ok((state.advance(close_idx + 1), options))
            Err(e) => Err(e)
          }
        }
        None => Err(unmatched_parenthesis_error(token))
      }
    }
    _ => Ok((state, []))
  }
}

/// ベース音をパース（スラッシュを含む）
fn parse_bass(state: ParserState, token: String) -> Result[(ParserState, Option[BassNote]), ParseError] {
  match state.current_char() {
    Some('/') => {
      let after_slash = state.advance(1)
      
      // アクシデンタルをパース
      let (after_acc, accidental) = parse_accidental(after_slash)
      
      // ディグリーをパース（必須）
      match parse_degree(after_acc, token) {
        Ok((after_deg, degree)) => {
          Ok((after_deg, Some(BassNote { accidental, degree })))
        }
        Err(_) => Err(missing_bass_degree_error(token))
      }
    }
    _ => Ok((state, None))
  }
}

/// コード文字列をパースしてChordNodeに変換
pub fn parse_chord(token: String) -> Result[ChordNode, ParseError] {
  let mut state = ParserState::new(token)
  
  // 1. アクシデンタル
  let (accidental_result) = parse_accidental(state)
  state = accidental_result.0
  let accidental = accidental_result.1
  
  // 2. ディグリー（必須）
  let degree = match parse_degree(state, token) {
    Ok((new_state, deg)) => {
      state = new_state
      deg
    }
    Err(e) => return Err(e)
  }
  
  // 3. クオリティ
  let (quality_result) = parse_quality(state)
  state = quality_result.0
  let quality = quality_result.1
  
  // 4. セブンス
  let seventh = match parse_seventh(state, token) {
    Ok((new_state, sev)) => {
      state = new_state
      sev
    }
    Err(e) => return Err(e)
  }
  
  // 5. オルタレーション（括弧外）
  let alteration = match parse_alteration(state, token) {
    Ok((new_state, alt)) => {
      state = new_state
      alt
    }
    Err(e) => return Err(e)
  }
  
  // 6. 括弧内オプション
  let options = match parse_parenthesized_options(state, token) {
    Ok((new_state, opts)) => {
      state = new_state
      opts
    }
    Err(e) => return Err(e)
  }
  
  // 7. ベース音
  let bass = match parse_bass(state, token) {
    Ok((new_state, b)) => {
      state = new_state
      b
    }
    Err(e) => return Err(e)
  }
  
  // パース完了チェック：残りの文字列がないことを確認
  if state.pos < state.length {
    return Err(unrecognized_token_error(token))
  }
  
  Ok(ChordNode {
    accidental,
    degree,
    quality,
    seventh,
    alteration,
    options,
    bass
  })
}

/// テスト用関数
pub fn test_parse_chord() -> Unit {
  let test_cases = [
    "1",
    "3m7",
    "4M7",
    "5",
    "b7",
    "s4",
    "1M7(b5,b9,s11)",
    "2m7(b5)",
    "5(b9)",
    "1M7(sus4,9)",
    "1/3",
    "4M7(b5,b9)/b3",
    "1sus4",
    "4M7b5",
    "1add9",
  ]
  
  for chord_str in test_cases {
    println("\nParsing: '\{chord_str}'")
    match parse_chord(chord_str) {
      Ok(node) => println("Success: \{chord_node_to_string(node)}")
      Err(e) => println("Error: \{e.to_string()}")
    }
  }
}

/// デバッグ用：ChordNodeを文字列に変換
fn chord_node_to_string(node: ChordNode) -> String {
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

fn option_to_string(opt: ChordOption) -> String {
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
