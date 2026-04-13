///| Lexerトークン（パース前の生の要素）
enum LexToken {
  ChordToken(String) // コード文字列（まだパースされていない）
  BarLineToken // |
  LineBreak // 改行
}

///|
pub struct LexResult {
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

///| 入力文字列を字句解析
pub fn tokenize(input : String) -> LexResult {
  let tokens : Array[LexToken] = []
  let current_token = @buffer.new()
  let chars = input.to_array()
  let len = chars.length()

  let mut i = 0
  while i < len {
    let c = chars[i]

    if is_whitespace(c) {
      // 空白文字：現在のトークンを確定
      if current_token.length() > 0 {
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
      if current_token.length() > 0 {
        tokens.push(ChordToken(current_token.to_string()))
        current_token.reset()
      }
      tokens.push(LineBreak)
      i = i + 1

    } else if is_barline(c) {
      // バーライン：現在のトークンを確定してBarLineTokenを追加
      if current_token.length() > 0 {
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
  if current_token.length() > 0 {
    tokens.push(ChordToken(current_token.to_string()))
  }
  { tokens, }
}

///| LexTokenを行に分割
pub fn group_by_lines(lex_result : LexResult) -> Array[Array[LexToken]] {
  let lines : Array[Array[LexToken]] = []
  let current_line : Array[LexToken] = []
  for token in lex_result.tokens {
    match token {
      LineBreak =>
        // 改行に到達：現在の行を確定（空行は無視）
        if current_line.length() > 0 {
          lines.push(current_line)
          current_line = []
        }
      _ =>
        // 改行以外：現在の行に追加
        current_line.push(token)
    }
  }

  // 最後の行を確定（空行でなければ）
  if current_line.length() > 0 {
    lines.push(current_line)
  }
  lines
}

///|
/// デバッグ用：LexTokenを文字列に変換
pub fn LexToken::to_string(self : LexToken) -> String {
  match self {
    ChordToken(s) => "Chord(\{s})"
    BarLineToken => "BarLine"
    LineBreak => "LineBreak"
  }
}

///|
/// デバッグ用：LexResultを文字列に変換
pub fn LexResult::to_string(self : LexResult) -> String {
  let parts = self.tokens.map(fn(t) { t.to_string() })
  "[" + parts.join(", ") + "]"
}

///|
/// 字句解析のテスト
pub fn test_tokenize() -> Unit {
  // テスト1: 基本的なコード列
  let input1 = "1 3m7 4M7 5"
  let result1 = tokenize(input1)
  println("Test 1: \{input1}")
  println("Result: \{result1.to_string()}")

  // テスト2: バーライン付き
  let input2 = "1 3m7 | 4M7 5"
  let result2 = tokenize(input2)
  println("\nTest 2: \{input2}")
  println("Result: \{result2.to_string()}")

  // テスト3: 改行付き
  let input3 = "1 3m7\n4M7 5"
  let result3 = tokenize(input3)
  println("\nTest 3: \{input3}")
  println("Result: \{result3.to_string()}")

  // テスト4: 複数スペース・タブ
  let input4 = "1  3m7\t\t4M7   5"
  let result4 = tokenize(input4)
  println("\nTest 4: 1  3m7\\t\\t4M7   5")
  println("Result: \{result4.to_string()}")

  // テスト5: 複雑な例
  let input5 = "1 3m7 4M7 5 | b7 1\ns4M7(b5,b9,s11) 5 |\n2m7(b5) 5(b9) 1M7(sus4,9)"
  let result5 = tokenize(input5)
  println("\nTest 5: Complex example")
  println("Result: \{result5.to_string()}")

  // 行分割のテスト
  let lines = group_by_lines(result5)
  println("\nGrouped by lines:")
  for i, line in lines.iter() {
    let line_str = line.map(fn(t) { t.to_string() }).join(", ")
    println("Line \{i + 1}: [\{line_str}]")
  }
}
