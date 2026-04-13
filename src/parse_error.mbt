///| パースエラーの種類
pub enum ParseErrorKind {
  // 構文エラー
  InvalidDegree(String) // 不正なディグリー（1-7以外）
  InvalidQuality(String) // 不正なクオリティ
  InvalidSeventh(String) // 不正なセブンス表記
  InvalidTension(String) // 不正なテンション表記
  InvalidOption(String) // 不正なオプション表記
  UnmatchedParenthesis // 括弧の不一致
  EmptyParentheses // 空の括弧 ()
  InvalidCommaUsage // カンマの不正使用
  UnrecognizedToken(String) // 認識できない文字列

  // 意味エラー
  DuplicateSeventh // セブンスの重複
  MissingBassDegree // スラッシュベースでディグリーが欠落
  InvalidSusDegree(String) // 不正なsusディグリー（2/4/6以外）
}

///| パースエラー
pub struct ParseError {
  kind : ParseErrorKind
  position : Int? // エラー位置（文字列内のインデックス）
  line : Int? // 行番号（1-indexed）
  token : String? // エラーが発生したトークン
}

///| エラーメッセージを生成
pub fn ParseError::message(self : ParseError) -> String {
  let base_msg = match self.kind {
    InvalidDegree(d) => "Invalid degree '\{d}' (must be 1-7)"
    InvalidQuality(q) => "Invalid quality '\{q}' (must be m, dim, or aug)"
    InvalidSeventh(s) => "Invalid seventh specification '\{s}'"
    InvalidTension(t) => "Invalid tension '\{t}'"
    InvalidOption(o) => "Invalid option '\{o}'"
    UnmatchedParenthesis => "Unmatched parenthesis"
    EmptyParentheses => "Empty parentheses are not allowed"
    InvalidCommaUsage =>
      "Invalid comma usage (leading, trailing, or consecutive commas)"
    UnrecognizedToken(t) => "Unrecognized token '\{t}'"
    DuplicateSeventh => "Duplicate seventh specification"
    MissingBassDegree => "Bass degree is required when slash is present"
    InvalidSusDegree(d) => "Invalid sus degree '\{d}' (must be 2, 4, or 6)"
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

///| エラーを文字列に変換
pub fn ParseError::to_string(self : ParseError) -> String {
  "ParseError: " + self.message()
}

///| 構文エラーを作成
pub fn ParseError::syntax(
  kind: ParseErrorKind,
  token?: Option[String] = None,
  position?: Option[Int] = None,
  line?: Option[Int] = None,
) -> ParseError {
  { kind, position, line, token }
}

///| 意味エラーを作成
pub fn ParseError::semantic(
  kind: ParseErrorKind,
  token?: Option[String] = None,
  position?: Option[Int] = None,
  line?: Option[Int] = None,
) -> ParseError {
  { kind, position, line, token }
}

pub fn invalid_degree_error(degree: String, token: String) -> ParseError {
  ParseError::syntax(InvalidDegree(degree), token=Some(token))
}

pub fn invalid_quality_error(quality: String, token: String) -> ParseError {
  ParseError::syntax(InvalidQuality(quality), token=Some(token))
}

pub fn invalid_seventh_error(seventh: String, token: String) -> ParseError {
  ParseError::syntax(InvalidSeventh(seventh), token=Some(token))
}

pub fn invalid_tension_error(tension: String, token: String) -> ParseError {
  ParseError::syntax(InvalidTension(tension), token=Some(token))
}

pub fn invalid_option_error(option: String, token: String) -> ParseError {
  ParseError::syntax(InvalidOption(option), token=Some(token))
}

pub fn unmatched_parenthesis_error(token: String) -> ParseError {
  ParseError::syntax(UnmatchedParenthesis, token=Some(token))
}

pub fn empty_parentheses_error(token: String) -> ParseError {
  ParseError::syntax(EmptyParentheses, token=Some(token))
}

pub fn invalid_comma_usage_error(token: String) -> ParseError {
  ParseError::syntax(InvalidCommaUsage, token=Some(token))
}

pub fn unrecognized_token_error(token: String) -> ParseError {
  ParseError::syntax(UnrecognizedToken(token), token=Some(token))
}

pub fn duplicate_seventh_error(token: String) -> ParseError {
  ParseError::semantic(DuplicateSeventh, token=Some(token))
}

pub fn missing_bass_degree_error(token: String) -> ParseError {
  ParseError::semantic(MissingBassDegree, token=Some(token))
}

pub fn invalid_sus_degree_error(degree: String, token: String) -> ParseError {
  ParseError::semantic(InvalidSusDegree(degree), token=Some(token))
}
