///|
/// 位置つき Lex トークンの種類
priv enum PosTokenKind {
  ChordTok // コード文字列（まだパースされていない）
  BarTok // |
  RepeatTok // %（反復記号）
}

///|
/// 位置つき Lex トークン
priv struct PosToken {
  text : String
  col : Int // 行内の開始位置（0-indexed）
  kind : PosTokenKind
}

///|
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
/// 1 行を字句解析する。
/// - `#` から行末まではコメント（仕様 v1.2.2）
/// - 括弧 `(` `)` の内側では空白でトークンを区切らない（`1M7(b9, s11)` を 1 トークンとして扱う）
fn tokenize_line(line : String) -> Array[PosToken] {
  let tokens : Array[PosToken] = []
  let chars = line.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    let c = chars[i]
    if is_whitespace(c) {
      i = i + 1
      continue
    }
    if c == '#' {
      // コメント: 行末まで無視
      break
    }
    if c == '|' {
      tokens.push({ text: "|", col: i, kind: BarTok })
      i = i + 1
      continue
    }
    if c == '%' {
      tokens.push({ text: "%", col: i, kind: RepeatTok })
      i = i + 1
      continue
    }
    // コードトークン: 括弧深度を追跡し、深度 0 の空白・|・# で終了
    let start = i
    let sb = StringBuilder::new()
    let mut depth = 0
    while i < len {
      let tc = chars[i]
      if depth == 0 &&
        (is_whitespace(tc) || tc == '|' || tc == '#' || tc == '%') {
        break
      }
      if tc == '(' {
        depth = depth + 1
      }
      if tc == ')' && depth > 0 {
        depth = depth - 1
      }
      sb.write_char(tc)
      i = i + 1
    }
    tokens.push({ text: sb.to_string(), col: start, kind: ChordTok })
  }
  tokens
}

///|
/// 入力全体を行に分割する（行番号は 1-indexed で保持される前提の配列。\r は字句解析側で無視）
fn split_lines(input : String) -> Array[String] {
  input.split("\n").map(fn(v) { v.to_owned() }).to_array()
}
