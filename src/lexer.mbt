///|
/// Lexerトークン（パース前の生の要素）
priv enum LexToken {
  ChordToken(String) // コード文字列（まだパースされていない）
  BarLineToken // |
  LineBreak // 改行
}

///|
priv struct LexResult {
  tokens : Array[LexToken]
}

///|
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
/// 文字が改行かどうかを判定
fn is_newline(c : Char) -> Bool {
  c == '\n'
}

///|
fn is_barline(c : Char) -> Bool {
  c == '|'
}

///|
/// 入力文字列を字句解析
fn tokenize(input : String) -> LexResult {
  let tokens : Array[LexToken] = []
  let current_token = StringBuilder::new()
  let chars = input.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    let c = chars[i]
    if is_whitespace(c) {
      // 空白文字：現在のトークンを確定
      if not(current_token.is_empty()) {
        tokens.push(ChordToken(current_token.to_string()))
        current_token.reset()
      }
      // 連続する空白はスキップ
      while i < len && is_whitespace(chars[i]) {
        i = i + 1
      }
      continue
    } else if is_newline(c) {
      // 改行：現在のトークンを確定してLineBreakを追加
      if not(current_token.is_empty()) {
        tokens.push(ChordToken(current_token.to_string()))
        current_token.reset()
      }
      tokens.push(LineBreak)
      i = i + 1
    } else if is_barline(c) {
      // バーライン：現在のトークンを確定してBarLineTokenを追加
      if not(current_token.is_empty()) {
        tokens.push(ChordToken(current_token.to_string()))
        current_token.reset()
      }
      tokens.push(BarLineToken)
      i = i + 1
    } else {
      // 通常の文字：現在のトークンに追加
      current_token.write_char(c)
      i = i + 1
    }
  }
  // 最後のトークンを確定
  if not(current_token.is_empty()) {
    tokens.push(ChordToken(current_token.to_string()))
  }
  { tokens, }
}

///|
/// LexTokenを行に分割（元ソースの行番号つき、空行はスキップ）
fn group_by_lines(lex_result : LexResult) -> Array[(Int, Array[LexToken])] {
  let lines : Array[(Int, Array[LexToken])] = []
  let mut current_line : Array[LexToken] = []
  let mut line_number = 1
  for token in lex_result.tokens {
    match token {
      LineBreak => {
        // 改行に到達：現在の行を確定（空行は無視するが行番号は進める）
        if current_line.length() > 0 {
          lines.push((line_number, current_line))
          current_line = []
        }
        line_number = line_number + 1
      }
      _ =>
        // 改行以外：現在の行に追加
        current_line.push(token)
    }
  }
  // 最後の行を確定（空行でなければ）
  if current_line.length() > 0 {
    lines.push((line_number, current_line))
  }
  lines
}
