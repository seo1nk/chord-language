///|
/// 位置つき Lex トークンの種類
priv enum PosTokenKind {
  ChordTok // コード文字列（まだパースされていない）
  BarTok // |
  RepeatTok // %（反復記号）
  BlankTok // _（空の拍）
  DirectiveTok // [key: 値] / [bpm: 値] / [time: 値]（指示。値が不正・未クローズでも拾い、エラーにする）
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
/// - `#` はシャープ記号としてトークンの一部になる（コメント構文は無い）
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
    if c == '_' && !(i + 1 < len && chars[i + 1] == '-') {
      // 単独の空拍。直後に - が続く場合はグループの先頭パート(_-5 など)
      // なので、ここでは切らずにコードトークンとしてスキャンする
      tokens.push({ text: "_", col: i, kind: BlankTok })
      i = i + 1
      continue
    }
    if c == '[' {
      // 転調指示トークン: トークン先頭の [ のみブラケット開始になり、
      // 内容が key（小文字）+ コロンで始まる場合だけ [ ... ] を 1 トークンにする。
      // それ以外の [ は従来どおり通常のトークン文字（[A] 1 4 → InvalidDegree を保存）
      let mut close = -1
      let mut j = i + 1
      while j < len {
        if chars[j] == ']' {
          close = j
          break
        }
        j = j + 1
      }
      if close >= 0 && is_directive_inner(chars, i + 1, close) {
        let sb = StringBuilder::new()
        for k in i..<(close + 1) {
          sb.write_char(chars[k])
        }
        tokens.push({ text: sb.to_string(), col: i, kind: DirectiveTok })
        i = close + 1
        continue
      }
      if close < 0 && is_directive_inner(chars, i + 1, len) {
        // 未クローズの転調指示: 行末までを 1 トークンとして拾う
        // （InvalidKeyChange として 1 件のエラーで報告するため）
        let sb = StringBuilder::new()
        for k in i..<len {
          sb.write_char(chars[k])
        }
        tokens.push({ text: sb.to_string(), col: i, kind: DirectiveTok })
        i = len
        continue
      }
    }
    // コードトークン: 括弧深度を追跡し、深度 0 の空白・|・%・_ で終了
    let start = i
    let sb = StringBuilder::new()
    let mut depth = 0
    while i < len {
      let tc = chars[i]
      // _ は原則トークンを区切るが、グループ区切り - の直後(5-_ など)は
      // グループの空きパートとしてトークンに含める(トークン先頭の _ は
      // 上の分岐で「次が -」のときだけここに来るので、切らずに含める)
      let blank_breaks = tc == '_' && i > start && chars[i - 1] != '-'
      if depth == 0 &&
        (is_whitespace(tc) || tc == '|' || tc == '%' || blank_breaks) {
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
/// 指示の名前(ディレクティブ予約領域のうち、意味を持つもの)
let directive_names : Array[String] = ["key", "bpm", "time"]

///|
/// ブラケットの内側（chars[start..end)）が指示のプレフィックス
/// （空白* 名前 空白* ":"。名前は key / bpm / time）で始まるなら、その名前を返す。
/// プレフィックスに一致したブラケットは値が不正でも指示として扱う
/// （タイポが黙ってセクションバッジ化する事故を防ぐ）。大文字の Key などは不一致
fn directive_name(chars : Array[Char], start : Int, end : Int) -> String? {
  let mut i = start
  while i < end && is_whitespace(chars[i]) {
    i = i + 1
  }
  for name in directive_names {
    let n = name.length()
    if i + n > end {
      continue
    }
    let mut ok = true
    for k, c in name.to_array() {
      if chars[i + k] != c {
        ok = false
        break
      }
    }
    if !ok {
      continue
    }
    let mut j = i + n
    while j < end && is_whitespace(chars[j]) {
      j = j + 1
    }
    if j < end && chars[j] == ':' {
      return Some(name)
    }
  }
  None
}

///|
fn is_directive_inner(chars : Array[Char], start : Int, end : Int) -> Bool {
  directive_name(chars, start, end) is Some(_)
}

///|
/// 入力全体を行に分割する（行番号は 1-indexed で保持される前提の配列。\r は字句解析側で無視）
fn split_lines(input : String) -> Array[String] {
  input.split("\n").map(fn(v) { v.to_owned() }).to_array()
}
