///|
/// フロントマター（v1.2）のパース。
///
/// ブロック先頭の `---` 行から次の `---` 行までを YAML 風のフィールド列として解釈する。
/// v1.2 で定義されるフィールドは `key` のみ。
/// 返り値: (メタデータ, エラー列, 本文の開始行インデックス)

///|
/// キー名の検証: A-G + 任意の #/b（メジャーキーのみ）
fn is_valid_key(s : String) -> Bool {
  let chars = s.to_array()
  match chars.length() {
    1 | 2 => {
      let head_ok = match chars[0] {
        'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' => true
        _ => false
      }
      if !head_ok {
        return false
      }
      if chars.length() == 2 {
        match chars[1] {
          '#' | 'b' => true
          _ => false
        }
      } else {
        true
      }
    }
    _ => false
  }
}

///|
/// フロントマターをパースする
fn parse_frontmatter(
  lines : Array[String],
) -> (ScoreMeta?, Array[ParseError], Int) {
  if lines.length() == 0 || lines[0].trim().to_owned() != "---" {
    return (None, [], 0)
  }
  // 閉じの --- を探す
  let mut close_idx = -1
  for idx in 1..<lines.length() {
    if lines[idx].trim().to_owned() == "---" {
      close_idx = idx
      break
    }
  }
  if close_idx < 0 {
    // 閉じられていないフロントマター: 以降を本文として扱わない
    return (None, [unclosed_frontmatter_error(1)], lines.length())
  }
  let errors : Array[ParseError] = []
  let mut key : String? = None
  let mut tempo : Int? = None
  let mut time : String? = None
  for idx in 1..<close_idx {
    let line = lines[idx].trim().to_owned()
    let line_no = idx + 1
    if line.is_empty() {
      continue
    }
    match line.find(":") {
      Some(colon_idx) => {
        let name = line
          .unsafe_substring(start=0, end=colon_idx)
          .trim()
          .to_owned()
        let value = line
          .unsafe_substring(start=colon_idx + 1, end=line.length())
          .trim()
          .to_owned()
        if name == "key" {
          if is_valid_key(value) {
            key = Some(value)
          } else {
            errors.push(invalid_key_error(value, line_no))
          }
        } else if name == "bpm" || name == "tempo" {
          // bpm が正式名（v1.7）。tempo は v1.6 の互換エイリアス
          match parse_tempo_value(value) {
            Some(bpm) => tempo = Some(bpm)
            None => errors.push(invalid_tempo_error(value, line_no))
          }
        } else if name == "time" {
          if is_valid_time_signature(value) {
            time = Some(value)
          } else {
            errors.push(invalid_time_signature_error(value, line_no))
          }
        } else {
          errors.push(invalid_frontmatter_field_error(name, line_no))
        }
      }
      None => errors.push(invalid_frontmatter_field_error(line, line_no))
    }
  }
  (Some({ key, tempo, time }), errors, close_idx + 1)
}

///|
/// 拍子の検証（一般的なもののみ許可するホワイトリスト制）
fn is_valid_time_signature(s : String) -> Bool {
  let allowed = [
    "1/2", "2/2", "2/4", "3/4", "4/4", "5/4", "6/4", "3/8", "6/8", "9/8", "12/8",
  ]
  allowed.contains(s)
}

///|
/// テンポ値の検証（整数 20-400）
fn parse_tempo_value(s : String) -> Int? {
  if s.is_empty() {
    return None
  }
  let mut n = 0
  for c in s {
    match c {
      '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
        n = n * 10 + (c.to_int() - 48)
      _ => return None
    }
    if n > 400 {
      return None
    }
  }
  if n < 20 {
    return None
  }
  Some(n)
}
