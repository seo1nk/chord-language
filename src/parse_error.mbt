///|
/// パースエラーの種類
pub enum ParseErrorKind {
  // 構文エラー
  InvalidDegree(String) // 不正なディグリー（1-7以外）
  InvalidSeventh(String) // 不正なセブンス表記
  InvalidTension(String) // 不正なテンション表記（括弧内の認識できない要素を含む）
  UnmatchedParenthesis // 括弧の不一致
  EmptyParentheses // 空の括弧 ()
  InvalidCommaUsage // カンマの不正使用
  InvalidColor(String) // 不正な色指定（blue/red/green以外）
  UnrecognizedToken(String) // 認識できない文字列

  // 意味エラー
  DuplicateSeventh // セブンスの重複
  MissingBassDegree // スラッシュベースでディグリーが欠落
  InvalidSusDegree(String) // 不正なsusディグリー（2/4/6以外）

  // フロントマターのエラー（v1.2）
  UnclosedFrontmatter // 閉じの --- が無い
  InvalidFrontmatterField(String) // 未知のフィールド（v1.2 は key のみ）
  InvalidKey(String) // 不正なキー名（A-G + 任意の #/b 以外）

  // 歌詞行のエラー（v1.4）
  TooManyLyricFragments(Int, Int) // (断片数, コード数) 断片がコード数を超過
  OrphanLyricLine // 直前の行がコード行でない歌詞行
}

///|
/// パースエラー
pub struct ParseError {
  kind : ParseErrorKind
  position : Int? // エラー位置（行内の 0-indexed 文字位置）
  line : Int? // 行番号（元ソース基準、1-indexed）
  token : String? // エラーが発生したトークン
}

///|
/// エラー種別の名前（構造化 JSON 用）
pub fn ParseError::kind_name(self : ParseError) -> String {
  match self.kind {
    InvalidDegree(_) => "InvalidDegree"
    InvalidSeventh(_) => "InvalidSeventh"
    InvalidTension(_) => "InvalidTension"
    UnmatchedParenthesis => "UnmatchedParenthesis"
    EmptyParentheses => "EmptyParentheses"
    InvalidCommaUsage => "InvalidCommaUsage"
    InvalidColor(_) => "InvalidColor"
    UnrecognizedToken(_) => "UnrecognizedToken"
    DuplicateSeventh => "DuplicateSeventh"
    MissingBassDegree => "MissingBassDegree"
    InvalidSusDegree(_) => "InvalidSusDegree"
    UnclosedFrontmatter => "UnclosedFrontmatter"
    InvalidFrontmatterField(_) => "InvalidFrontmatterField"
    InvalidKey(_) => "InvalidKey"
    TooManyLyricFragments(_, _) => "TooManyLyricFragments"
    OrphanLyricLine => "OrphanLyricLine"
  }
}

///|
/// エラーメッセージを生成
pub fn ParseError::message(self : ParseError) -> String {
  let base_msg = match self.kind {
    InvalidDegree(d) => "Invalid degree '\{d}' (must be 1-7)"
    InvalidSeventh(s) => "Invalid seventh specification '\{s}'"
    InvalidTension(t) => "Invalid tension '\{t}'"
    UnmatchedParenthesis => "Unmatched parenthesis"
    EmptyParentheses => "Empty parentheses are not allowed"
    InvalidCommaUsage =>
      "Invalid comma usage (leading, trailing, or consecutive commas)"
    InvalidColor(c) => "Invalid color '\{c}' (must be blue, red, or green)"
    UnrecognizedToken(t) => "Unrecognized token '\{t}'"
    DuplicateSeventh => "Duplicate seventh specification"
    MissingBassDegree => "Bass degree is required when slash is present"
    InvalidSusDegree(d) => "Invalid sus degree '\{d}' (must be 2, 4, or 6)"
    UnclosedFrontmatter => "Frontmatter is not closed (missing '---')"
    InvalidFrontmatterField(f) =>
      "Invalid frontmatter field '\{f}' (only 'key' is allowed)"
    InvalidKey(k) => "Invalid key '\{k}' (must be A-G with optional # or b)"
    TooManyLyricFragments(got, expected) =>
      "Too many lyric fragments (got \{got}, expected at most \{expected})"
    OrphanLyricLine => "Lyric line must directly follow a chord line"
  }
  let token_info = match self.token {
    Some(t) => " in '\{t}'"
    None => ""
  }
  let position_info = match (self.line, self.position) {
    (Some(line), Some(pos)) => " at line \{line}, position \{pos}"
    (Some(line), None) => " at line \{line}"
    (None, Some(pos)) => " at position \{pos}"
    (None, None) => ""
  }
  base_msg + token_info + position_info
}

///|
/// エラーを文字列に変換
pub fn ParseError::to_string(self : ParseError) -> String {
  "ParseError: " + self.message()
}

///|
/// エラーを構造化 JSON に変換
pub fn ParseError::to_json_value(self : ParseError) -> Json {
  let obj : Map[String, Json] = {}
  obj["kind"] = Json::string(self.kind_name())
  obj["message"] = Json::string(self.message())
  match self.line {
    Some(l) => obj["line"] = Json::number(l.to_double())
    None => ()
  }
  match self.position {
    Some(p) => obj["position"] = Json::number(p.to_double())
    None => ()
  }
  match self.token {
    Some(t) => obj["token"] = Json::string(t)
    None => ()
  }
  Json::object(obj)
}

///|
/// エラーに行番号を付与する（未設定の場合のみ上書き）
pub fn ParseError::with_line(self : ParseError, line : Int) -> ParseError {
  {
    kind: self.kind,
    position: self.position,
    line: Some(line),
    token: self.token,
  }
}

///|
/// トークン内位置を行内位置へシフトする
pub fn ParseError::shift_position(self : ParseError, base : Int) -> ParseError {
  let position = match self.position {
    Some(p) => Some(base + p)
    None => Some(base)
  }
  { kind: self.kind, position, line: self.line, token: self.token }
}

///|
pub fn invalid_degree_error(
  degree : String,
  token : String,
  pos : Int,
) -> ParseError {
  {
    kind: InvalidDegree(degree),
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn invalid_seventh_error(
  seventh : String,
  token : String,
  pos : Int,
) -> ParseError {
  {
    kind: InvalidSeventh(seventh),
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn invalid_tension_error(
  tension : String,
  token : String,
  pos : Int,
) -> ParseError {
  {
    kind: InvalidTension(tension),
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn unmatched_parenthesis_error(token : String, pos : Int) -> ParseError {
  {
    kind: UnmatchedParenthesis,
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn empty_parentheses_error(token : String, pos : Int) -> ParseError {
  {
    kind: EmptyParentheses,
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn invalid_comma_usage_error(token : String, pos : Int) -> ParseError {
  {
    kind: InvalidCommaUsage,
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn invalid_color_error(
  color : String,
  token : String,
  pos : Int,
) -> ParseError {
  {
    kind: InvalidColor(color),
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn unrecognized_token_error(token : String, pos : Int) -> ParseError {
  {
    kind: UnrecognizedToken(token),
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn duplicate_seventh_error(token : String, pos : Int) -> ParseError {
  {
    kind: DuplicateSeventh,
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn missing_bass_degree_error(token : String, pos : Int) -> ParseError {
  {
    kind: MissingBassDegree,
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn invalid_sus_degree_error(
  degree : String,
  token : String,
  pos : Int,
) -> ParseError {
  {
    kind: InvalidSusDegree(degree),
    position: Some(pos),
    line: None,
    token: Some(token),
  }
}

///|
pub fn unclosed_frontmatter_error(line : Int) -> ParseError {
  { kind: UnclosedFrontmatter, position: None, line: Some(line), token: None }
}

///|
pub fn invalid_frontmatter_field_error(
  field : String,
  line : Int,
) -> ParseError {
  {
    kind: InvalidFrontmatterField(field),
    position: None,
    line: Some(line),
    token: None,
  }
}

///|
pub fn invalid_key_error(key : String, line : Int) -> ParseError {
  { kind: InvalidKey(key), position: None, line: Some(line), token: None }
}

///|
pub fn too_many_lyric_fragments_error(
  got : Int,
  expected : Int,
  line : Int,
) -> ParseError {
  {
    kind: TooManyLyricFragments(got, expected),
    position: None,
    line: Some(line),
    token: None,
  }
}

///|
pub fn orphan_lyric_line_error(line : Int) -> ParseError {
  { kind: OrphanLyricLine, position: None, line: Some(line), token: None }
}
