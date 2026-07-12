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
  InvalidQuartalCombination // q に付加要素(セブンス・sus・テンション等)が続いた

  // フロントマターのエラー
  UnclosedFrontmatter // 閉じの --- が無い
  InvalidFrontmatterField(String) // 未知のフィールド
  InvalidKey(String) // 不正なキー名（A-G + 任意の #/b 以外）
  InvalidTempo(String) // 不正な bpm（整数 20-400 以外）
  InvalidTimeSignature(String) // 不正な拍子（ホワイトリスト外）

  // 転調指示のエラー
  InvalidKeyChange(String) // 不正な転調指示（不正な値・値の欠落・未クローズ）

  // 歌詞行のエラー
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
    InvalidQuartalCombination => "InvalidQuartalCombination"
    UnclosedFrontmatter => "UnclosedFrontmatter"
    InvalidFrontmatterField(_) => "InvalidFrontmatterField"
    InvalidKey(_) => "InvalidKey"
    InvalidTempo(_) => "InvalidTempo"
    InvalidTimeSignature(_) => "InvalidTimeSignature"
    InvalidKeyChange(_) => "InvalidKeyChange"
    TooManyLyricFragments(_, _) => "TooManyLyricFragments"
    OrphanLyricLine => "OrphanLyricLine"
  }
}

///|
/// エラーメッセージを生成
pub fn ParseError::message(self : ParseError) -> String {
  let base_msg = match self.kind {
    InvalidDegree(d) => "不正なディグリー '\{d}'(1〜7 で書きます)"
    InvalidSeventh(s) => "不正なセブンス表記 '\{s}'"
    InvalidTension(t) => "不正なテンション '\{t}'"
    UnmatchedParenthesis => "括弧が閉じていません"
    EmptyParentheses => "空の括弧 () は使えません"
    InvalidCommaUsage =>
      "カンマの使い方が不正です(先頭・末尾・連続は不可)"
    InvalidColor(c) => "不正な色 '\{c}'(blue / red / green のみ)"
    UnrecognizedToken(t) => "認識できないトークン '\{t}'"
    DuplicateSeventh => "セブンスが重複しています"
    MissingBassDegree =>
      "スラッシュの後にはベースのディグリーが必要です"
    InvalidSusDegree(d) =>
      "不正な sus ディグリー '\{d}'(2 / 4 / 6 のみ)"
    InvalidQuartalCombination =>
      "q(4度堆積)にはセブンスや sus・テンションなどを付けられません"
    UnclosedFrontmatter =>
      "フロントマターが閉じていません(--- が必要)"
    InvalidFrontmatterField(f) =>
      "未知のフロントマターフィールド '\{f}'(key / bpm / time のみ)"
    InvalidKey(k) => "不正なキー '\{k}'(A〜G + 任意の # / b)"
    InvalidTempo(t) => "不正な bpm '\{t}'(20〜400 の整数)"
    InvalidTimeSignature(t) =>
      "不正な拍子 '\{t}'(使えるのは 1/2 2/2 2/4 3/4 4/4 5/4 6/4 3/8 6/8 9/8 12/8)"
    InvalidKeyChange(v) =>
      "不正な転調指示 '\{v}'(書き方は [key: +2] / [key: F]。相対は半音 1〜11、絶対キーは A〜G + 任意の # / b)"
    TooManyLyricFragments(got, expected) =>
      if expected == 0 {
        // 転調指示行・小節線だけの行など、割り当て先スロットが 0 の行への歌詞
        "歌詞を割り当てるスロットが直前の行にありません(歌詞行はコード行の直後に書きます。転調指示行には付けられません)"
      } else {
        "歌詞の断片が多すぎます(\{got} 個。割り当て先は最大 \{expected} 個)"
      }
    OrphanLyricLine => "歌詞行(>)は直前にコード行が必要です"
  }
  let token_info = match self.token {
    Some(t) => " — '\{t}'"
    None => ""
  }
  let position_info = match (self.line, self.position) {
    (Some(line), Some(pos)) => "(\{line} 行目, 位置 \{pos})"
    (Some(line), None) => "(\{line} 行目)"
    (None, Some(pos)) => "(位置 \{pos})"
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
pub fn invalid_quartal_combination_error(
  token : String,
  pos : Int,
) -> ParseError {
  {
    kind: InvalidQuartalCombination,
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
pub fn invalid_key_change_error(token : String, pos : Int) -> ParseError {
  {
    kind: InvalidKeyChange(token),
    position: Some(pos),
    line: None,
    token: Some(token),
  }
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

///|
pub fn invalid_tempo_error(tempo : String, line : Int) -> ParseError {
  { kind: InvalidTempo(tempo), position: None, line: Some(line), token: None }
}

///|
pub fn invalid_time_signature_error(time : String, line : Int) -> ParseError {
  {
    kind: InvalidTimeSignature(time),
    position: None,
    line: Some(line),
    token: None,
  }
}
