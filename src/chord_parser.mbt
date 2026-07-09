///|
/// パース状態を保持する構造体
priv struct ParserState {
  input : String
  pos : Int
  length : Int
}

///|
/// ParserStateのコンストラクタ
fn ParserState::new(input : String) -> ParserState {
  { input, pos: 0, length: input.length() }
}

///|
/// 現在位置の文字を取得（範囲外ならNone）
fn ParserState::current_char(self : ParserState) -> Char? {
  self.input.get_char(self.pos)
}

///|
/// 位置を進める
fn ParserState::advance(self : ParserState, n : Int) -> ParserState {
  { input: self.input, pos: self.pos + n, length: self.length }
}

///|
/// 現在位置から指定文字数の文字列を取得
fn ParserState::take(self : ParserState, n : Int) -> String {
  self.input.unsafe_substring(start=self.pos, end=self.pos + n)
}

///|
/// 残りの文字列を取得
fn ParserState::remaining(self : ParserState) -> String {
  self.input.unsafe_substring(start=self.pos, end=self.length)
}

///|
/// アクシデンタルをパース（シャープは `s` と `#` の両方を受理）
fn parse_accidental(state : ParserState) -> (ParserState, Accidental?) {
  match state.current_char() {
    Some('s') | Some('#') => (state.advance(1), Some(Sharp))
    Some('b') => (state.advance(1), Some(Flat))
    _ => (state, None)
  }
}

///|
/// ディグリーをパース
fn parse_degree(
  state : ParserState,
  token : String,
) -> Result[(ParserState, Degree), ParseError] {
  match state.current_char() {
    Some(c) =>
      match Degree::from_char(c) {
        Some(degree) => Ok((state.advance(1), degree))
        None => Err(invalid_degree_error(c.to_string(), token, state.pos))
      }
    None => Err(invalid_degree_error("", token, state.pos))
  }
}

///|
/// クオリティをパース
fn parse_quality(state : ParserState) -> (ParserState, Quality?) {
  // "dim" (3文字) をチェック
  if state.pos + 3 <= state.length && state.take(3) == "dim" {
    return (state.advance(3), Some(Diminish))
  }
  // "aug" (3文字) をチェック
  if state.pos + 3 <= state.length && state.take(3) == "aug" {
    return (state.advance(3), Some(Augment))
  }
  // "maj7"(メジャーセブンスの別表記)はクオリティではないので消費しない
  if state.pos + 4 <= state.length && state.take(4) == "maj7" {
    return (state, None)
  }
  // "m" / "q" (1文字) をチェック
  match state.current_char() {
    Some('m') => (state.advance(1), Some(Minor))
    Some('q') => (state.advance(1), Some(Quartal))
    _ => (state, None)
  }
}

///|
/// セブンスをパース（優先順位: M7 → 7 → 6 → add系）
fn parse_seventh(
  state : ParserState,
  token : String,
) -> Result[(ParserState, Seventh?), ParseError] {
  // maj7 をチェック（4文字。M7 の別表記）
  if state.pos + 4 <= state.length && state.take(4) == "maj7" {
    return Ok((state.advance(4), Some(MajorSeventh)))
  }
  // M7 をチェック（2文字）
  if state.pos + 2 <= state.length && state.take(2) == "M7" {
    return Ok((state.advance(2), Some(MajorSeventh)))
  }
  // 7 / 6 をチェック（1文字）
  match state.current_char() {
    Some('7') => return Ok((state.advance(1), Some(Seventh)))
    Some('6') => return Ok((state.advance(1), Some(Sixth)))
    _ => ()
  }
  // add系をチェック
  if state.pos + 3 <= state.length && state.take(3) == "add" {
    let after_add = state.advance(3)
    // addの後のディグリーを取得
    let remaining = after_add.remaining()

    // 2桁の数字をチェック（11, 13）
    if remaining.length() >= 2 {
      let two_chars = remaining.unsafe_substring(start=0, end=2)
      match AddDegree::from_string(two_chars) {
        Some(degree) => return Ok((after_add.advance(2), Some(Add(degree))))
        None => ()
      }
    }

    // 1桁の数字をチェック（2, 4, 6, 9）
    if remaining.length() >= 1 {
      let one_char = remaining.unsafe_substring(start=0, end=1)
      match AddDegree::from_string(one_char) {
        Some(degree) => return Ok((after_add.advance(1), Some(Add(degree))))
        None =>
          return Err(
            invalid_seventh_error("add" + one_char, token, after_add.pos),
          )
      }
    }
    return Err(invalid_seventh_error("add", token, state.pos))
  }
  Ok((state, None))
}

///|
/// オルタレーション（括弧外）をパース
fn parse_alteration(
  state : ParserState,
  token : String,
  allow_dash_five : Bool,
) -> Result[(ParserState, Alteration?), ParseError] {
  // b5 をチェック
  if state.pos + 2 <= state.length && state.take(2) == "b5" {
    return Ok((state.advance(2), Some(FlatFive)))
  }
  // -5（ハーフディミニッシュの慣用表記 m7-5。クオリティ m +
  // セブンス 7 の直後のみ。`-` はグループ区切りと衝突するため）
  if allow_dash_five && state.pos + 2 <= state.length && state.take(2) == "-5" {
    return Ok((state.advance(2), Some(FlatFive)))
  }
  // sus をチェック
  if state.pos + 3 <= state.length && state.take(3) == "sus" {
    let after_sus = state.advance(3)
    match after_sus.current_char() {
      Some(c) =>
        match Degree::from_char(c) {
          Some(degree) =>
            // sus度数の妥当性チェック（2, 4, 6のみ）
            match degree {
              D2 | D4 | D6 => Ok((after_sus.advance(1), Some(Sus(degree))))
              _ =>
                Err(
                  invalid_sus_degree_error(c.to_string(), token, after_sus.pos),
                )
            }
          None =>
            Err(invalid_sus_degree_error(c.to_string(), token, after_sus.pos))
        }
      None => Err(invalid_sus_degree_error("", token, after_sus.pos))
    }
  } else {
    Ok((state, None))
  }
}

///|
/// テンションをパース
fn parse_tension(
  s : String,
  token : String,
  pos : Int,
) -> Result[Tension, ParseError] {
  match s {
    "b9" => Ok(FlatNine)
    "9" => Ok(Nine)
    "s9" | "#9" => Ok(SharpNine)
    "11" => Ok(Eleven)
    "s11" | "#11" => Ok(SharpEleven)
    "b13" => Ok(FlatThirteen)
    "13" => Ok(Thirteen)
    _ => Err(invalid_tension_error(s, token, pos))
  }
}

///|
/// 括弧内オプションの1つをパース（pos はトークン内でのこのオプションの開始位置）
fn parse_single_option(
  s : String,
  token : String,
  pos : Int,
) -> Result[ChordOption, ParseError] {
  let trimmed = s.trim().to_owned()

  // b5 をチェック
  if trimmed == "b5" {
    return Ok(AlterationOpt(FlatFive))
  }

  // sus をチェック（sus で始まる文字列は度数を検証し、2/4/6 以外は InvalidSusDegree）
  if trimmed.has_prefix("sus") {
    if trimmed.length() == 4 {
      match trimmed.get_char(3) {
        Some(degree_char) =>
          match Degree::from_char(degree_char) {
            Some(degree) =>
              match degree {
                D2 | D4 | D6 => return Ok(AlterationOpt(Sus(degree)))
                _ =>
                  return Err(
                    invalid_sus_degree_error(
                      degree_char.to_string(),
                      token,
                      pos,
                    ),
                  )
              }
            None =>
              return Err(
                invalid_sus_degree_error(degree_char.to_string(), token, pos),
              )
          }
        None => ()
      }
    }
    // "sus"（度数なし）や "sus11" 等もここに落ちる
    let degree_str = trimmed.unsafe_substring(start=3, end=trimmed.length())
    return Err(invalid_sus_degree_error(degree_str, token, pos))
  }
  // テンションとしてパース
  match parse_tension(trimmed, token, pos) {
    Ok(tension) => Ok(TensionOpt(tension))
    Err(e) => Err(e)
  }
}

///|
/// 括弧内オプションをパース（base_pos は括弧内容のトークン内開始位置）
fn parse_options(
  content : String,
  token : String,
  base_pos : Int,
) -> Result[Array[ChordOption], ParseError] {
  // 空の括弧チェック
  if content.trim().is_empty() {
    return Err(empty_parentheses_error(token, base_pos - 1))
  }
  // カンマで分割しつつ、各パートのオフセットを記録
  let parts : Array[String] = []
  let offsets : Array[Int] = []
  let mut off = 0
  for v in content.split(",") {
    let s = v.to_owned()
    parts.push(s)
    offsets.push(off)
    off = off + s.length() + 1
  }
  let options : Array[ChordOption] = []

  // カンマの不正使用チェック
  for i, part in parts {
    if part.trim().is_empty() {
      return Err(invalid_comma_usage_error(token, base_pos + offsets[i]))
    }
  }

  // 各オプションをパース
  for i, part in parts {
    match parse_single_option(part, token, base_pos + offsets[i]) {
      Ok(option) => options.push(option)
      Err(e) => return Err(e)
    }
  }
  Ok(options)
}

///|
/// 括弧内オプションをパース（括弧を含む）
fn parse_parenthesized_options(
  state : ParserState,
  token : String,
) -> Result[(ParserState, Array[ChordOption]), ParseError] {
  match state.current_char() {
    Some('(') => {
      // 閉じ括弧を探す
      let remaining = state.remaining()
      match remaining.find(")") {
        Some(close_idx) => {
          // 括弧内の内容を取得
          let content = remaining.unsafe_substring(start=1, end=close_idx)
          match parse_options(content, token, state.pos + 1) {
            Ok(options) => Ok((state.advance(close_idx + 1), options))
            Err(e) => Err(e)
          }
        }
        None => Err(unmatched_parenthesis_error(token, state.pos))
      }
    }
    _ => Ok((state, []))
  }
}

///|
/// ベース音をパース（スラッシュを含む）
fn parse_bass(
  state : ParserState,
  token : String,
) -> Result[(ParserState, BassNote?), ParseError] {
  match state.current_char() {
    Some('/') => {
      let after_slash = state.advance(1)
      // アクシデンタルをパース
      let (after_acc, accidental) = parse_accidental(after_slash)
      // ディグリーをパース（必須）
      match parse_degree(after_acc, token) {
        Ok((after_deg, degree)) => Ok((after_deg, Some({ accidental, degree })))
        Err(e) =>
          // 度数の文字自体が無い場合のみ MissingBassDegree（"1/8" は InvalidDegree('8') を伝播）
          match after_acc.current_char() {
            None => Err(missing_bass_degree_error(token, after_acc.pos))
            Some(_) => Err(e)
          }
      }
    }
    _ => Ok((state, None))
  }
}

///|
/// 色アノテーションをパース（@blue / @red / @green、トークン末尾のみ）
fn parse_color(
  state : ParserState,
  token : String,
) -> Result[(ParserState, ChordColor?), ParseError] {
  match state.current_char() {
    Some('@') => {
      let name = state.advance(1).remaining()
      match ChordColor::from_string(name) {
        Some(color) => Ok((state.advance(1 + name.length()), Some(color)))
        None => Err(invalid_color_error(name, token, state.pos))
      }
    }
    _ => Ok((state, None))
  }
}

///|
/// コード文字列をパースしてChordNodeに変換。
/// エラーの position はトークン内の 0-indexed 位置（呼び出し側が行内位置へシフトする）。
pub fn parse_chord(token : String) -> Result[ChordNode, ParseError] {
  let mut state = ParserState::new(token)

  // 1. アクシデンタル
  let (after_acc, accidental) = parse_accidental(state)
  state = after_acc

  // 2. ディグリー（必須）
  let degree = match parse_degree(state, token) {
    Ok((new_state, deg)) => {
      state = new_state
      deg
    }
    Err(e) => return Err(e)
  }

  // 3. クオリティ
  let (after_quality, quality) = parse_quality(state)
  state = after_quality

  // 4. セブンス
  let quartal_extras_pos = state.pos // q に不正な付加が続いた場合のエラー位置
  let seventh = match parse_seventh(state, token) {
    Ok((new_state, sev)) => {
      state = new_state
      sev
    }
    Err(e) => return Err(e)
  }

  // 4b. セブンスの重複チェック（1M77 / 17M7 / 1M7add9 など）
  if seventh is Some(_) {
    match parse_seventh(state, token) {
      Ok((_, Some(_))) => return Err(duplicate_seventh_error(token, state.pos))
      _ => ()
    }
  }

  // 5. オルタレーション（括弧外）。-5 は m7 の直後のみ受理する
  let allow_dash_five = quality is Some(Minor) && seventh is Some(Seventh)
  let alteration = match parse_alteration(state, token, allow_dash_five) {
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

  // 6b. q（4度堆積）はセブンス・sus/b5・テンションと組み合わせ不可
  if quality is Some(Quartal) &&
    (seventh is Some(_) || alteration is Some(_) || options.length() > 0) {
    return Err(invalid_quartal_combination_error(token, quartal_extras_pos))
  }

  // 7. ベース音
  let bass = match parse_bass(state, token) {
    Ok((new_state, b)) => {
      state = new_state
      b
    }
    Err(e) => return Err(e)
  }

  // 8. 色アノテーション（末尾）
  let color = match parse_color(state, token) {
    Ok((new_state, c)) => {
      state = new_state
      c
    }
    Err(e) => return Err(e)
  }

  // パース完了チェック：残りの文字列がないことを確認
  if state.pos < state.length {
    return Err(unrecognized_token_error(token, state.pos))
  }
  Ok({ accidental, degree, quality, seventh, alteration, options, bass, color })
}
