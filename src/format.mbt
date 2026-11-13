///|
/// コード譜ブロックを整形する(v1.3)。
///
/// 約束:
/// - 行数を変えない(n 行目は n 行目のまま。エディタのカーソルの行を保つため)
/// - 意味を変えない(整形の前後で parse の結果が同じ)。何度かけても同じ結果になる
/// - 正しく読めた行だけを整える。エラーのある行と、その行に付いた歌詞行は、
///   行末の空白を落とすだけにする(書きかけを壊さない)
/// - コード記号の綴りは書いたとおりに残す(#4 と s4、M7 と maj7 などを書き換えない)
///
/// 整え方:
/// - フロントマター: `key: G` の形(コロンの後に空白 1 つ)
/// - セクション: `[名前]`(角括弧の内側の前後の空白を除く)
/// - 指示: `[key: +2]` `[bpm: 140]` `[time: 3/4]`
/// - コード行: トークンの間を空白 1 つ(小節線の前後も)
/// - 歌詞行: `> ` + 断片を空白 1 つで区切る。直前のコード行と縦をそろえ、
///   各スロットの書き始めの位置に、そのスロットの歌詞の書き始めを置く
///   (全角などの幅 2 の文字は 2 桁として数える)
pub fn format_score(input : String) -> String {
  let lines = split_lines(input)
  let result = parse(input)
  let error_lines : Map[Int, Bool] = {}
  for e in result.errors {
    match e.line {
      Some(l) => error_lines[l] = true
      None => ()
    }
  }
  // 正しく読めたコード行(行番号 → 行)
  let code_lines : Map[Int, Line] = {}
  for line in result.score.lines {
    if !error_lines.contains(line.line_number) {
      code_lines[line.line_number] = line
    }
  }
  let out : Array[String] = lines.map(fn(l) { rstrip(l) })
  let body_start = format_frontmatter(lines, out, result.errors.length() > 0)
  let mut idx = body_start
  while idx < lines.length() {
    let line_no = idx + 1
    let trimmed = lines[idx].trim().to_owned()
    if trimmed == "" {
      out[idx] = ""
      idx = idx + 1
      continue
    }
    if error_lines.contains(line_no) {
      idx = idx + 1
      continue
    }
    match code_lines.get(line_no) {
      Some(_) => {
        // 次の行が、この行に付いた正しい歌詞行なら、縦をそろえて 2 行まとめて整える
        let lyric_idx = idx + 1
        let has_lyric = lyric_idx < lines.length() &&
          lines[lyric_idx].trim().to_owned().has_prefix(">") &&
          !error_lines.contains(lyric_idx + 1)
        if has_lyric {
          let (code, lyric) = format_code_with_lyric(
            lines[idx],
            lines[lyric_idx],
          )
          out[idx] = code
          out[lyric_idx] = lyric
          idx = idx + 2
        } else {
          out[idx] = format_code_line(lines[idx])
          idx = idx + 1
        }
      }
      None => {
        let chars = trimmed.to_array()
        if chars[0] == '[' &&
          chars[chars.length() - 1] == ']' &&
          !is_directive_inner(chars, 1, chars.length()) {
          // セクションラベル
          out[idx] = "[" +
            trimmed
            .unsafe_substring(start=1, end=trimmed.length() - 1)
            .trim()
            .to_owned() +
            "]"
        } else if chars[0] == '>' {
          // 付き先の無い歌詞行(エラーになっていなければここには来ない)。空白だけそろえる
          out[idx] = format_lyric_plain(trimmed)
        }
        idx = idx + 1
      }
    }
  }
  out.join("\n")
}

///|
/// 行末の空白を落とす
fn rstrip(s : String) -> String {
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 && is_whitespace(chars[end - 1]) {
    end = end - 1
  }
  String::from_array(chars[0:end].to_owned())
}

///|
/// フロントマターを整え、本文の開始行を返す。閉じていない・エラーのある
/// フロントマターは、行末の空白を落とすだけにする
fn format_frontmatter(
  lines : Array[String],
  out : Array[String],
  _has_errors : Bool,
) -> Int {
  if lines.length() == 0 || lines[0].trim().to_owned() != "---" {
    return 0
  }
  let mut close_idx = -1
  for idx in 1..<lines.length() {
    if lines[idx].trim().to_owned() == "---" {
      close_idx = idx
      break
    }
  }
  if close_idx < 0 {
    return lines.length()
  }
  out[0] = "---"
  out[close_idx] = "---"
  for idx in 1..<close_idx {
    let line = lines[idx].trim().to_owned()
    match line.find(":") {
      Some(colon) => {
        let name = line.unsafe_substring(start=0, end=colon).trim()
        let value = line
          .unsafe_substring(start=colon + 1, end=line.length())
          .trim()
        out[idx] = name.to_owned() + ": " + value.to_owned()
      }
      None => out[idx] = line
    }
  }
  close_idx + 1
}

///|
/// 正しく読めたコード行のトークンを、整えた表記の列にする
/// (返り値: (表記, スロットか))。指示は正規の形に直す
fn format_tokens(line : String) -> Array[(String, Bool)] {
  tokenize_line(line).map(fn(pt) {
    match pt.kind {
      BarTok => (pt.text, false)
      DirectiveTok =>
        match parse_directive_token(pt.text) {
          Ok(KeyChangeTok(kc)) => ("[key: " + kc.to_source_text() + "]", false)
          Ok(TempoChangeTok(bpm)) => ("[bpm: " + bpm.to_string() + "]", false)
          Ok(TimeChangeTok(time)) => ("[time: " + time + "]", false)
          _ => (pt.text, false)
        }
      RepeatTok | BlankTok | ChordTok => (pt.text, true)
    }
  })
}

///|
fn format_code_line(line : String) -> String {
  format_tokens(line).map(fn(t) { t.0 }).join(" ")
}

///|
/// 歌詞の断片(空白区切り)
fn lyric_fragments_raw(trimmed : String) -> Array[String] {
  let body = trimmed.unsafe_substring(start=1, end=trimmed.length())
  body
  .split(" ")
  .flat_map(fn(v) { v.split("\t") })
  .map(fn(v) { v.to_owned() })
  .filter(fn(v) { v != "" })
  .to_array()
}

///|
fn format_lyric_plain(trimmed : String) -> String {
  let frags = lyric_fragments_raw(trimmed)
  if frags.is_empty() {
    ">"
  } else {
    "> " + frags.join(" ")
  }
}

///|
/// コード行と、その下の歌詞行を、縦をそろえて整える。
/// 各スロットの書き始めの桁に、そのスロットの歌詞の書き始めを置く。
/// スロットの幅は max(コードの幅, 歌詞の幅) とし、次のトークンはその後ろから始める
fn format_code_with_lyric(code : String, lyric : String) -> (String, String) {
  let tokens = format_tokens(code)
  let frags = lyric_fragments_raw(lyric.trim().to_owned())
  let code_sb = StringBuilder::new()
  let lyric_sb = StringBuilder::new()
  let mut code_col = 0
  // 歌詞行は "> " の 2 桁から始まるので、最初のスロットが 2 桁目より前なら字下げする
  let mut first_slot_col = -1
  let mut probe = 0
  for i, t in tokens {
    if i > 0 {
      probe = probe + 1
    }
    if t.1 {
      first_slot_col = probe
      break
    }
    probe = probe + display_width(t.0)
  }
  let indent = if first_slot_col >= 0 && first_slot_col < 2 {
    2 - first_slot_col
  } else {
    0
  }
  for _k in 0..<indent {
    code_sb.write_char(' ')
  }
  code_col = indent
  lyric_sb.write_string(">")
  let mut lyric_col = 1
  let mut slot = 0
  for i, t in tokens {
    let (text, is_slot) = t
    if i > 0 {
      code_sb.write_char(' ')
      code_col = code_col + 1
    }
    let mut width = display_width(text)
    if is_slot {
      if slot < frags.length() {
        let frag = frags[slot]
        // 歌詞を、このスロットの書き始めの桁に置く(最低 1 つは空白を空ける)
        let target = if code_col > lyric_col { code_col } else { lyric_col + 1 }
        for _k in lyric_col..<target {
          lyric_sb.write_char(' ')
        }
        lyric_sb.write_string(frag)
        let fw = display_width(frag)
        lyric_col = target + fw
        // 歌詞がコードより広ければ、コードの側を伸ばして次のスロットとそろえる
        if target == code_col && fw > width {
          width = fw
        }
      }
      slot = slot + 1
    }
    code_sb.write_string(text)
    let pad = width - display_width(text)
    let is_last = i == tokens.length() - 1
    if !is_last {
      for _k in 0..<pad {
        code_sb.write_char(' ')
      }
      code_col = code_col + width
    } else {
      code_col = code_col + display_width(text)
    }
  }
  (rstrip(code_sb.to_string()), rstrip(lyric_sb.to_string()))
}

///|
/// 等幅の画面での表示幅(全角・CJK・絵文字などは 2)
fn display_width(s : String) -> Int {
  let mut w = 0
  for c in s {
    let cp = c.to_int()
    let wide = (cp >= 0x1100 && cp <= 0x115F) ||
      (cp >= 0x2E80 && cp <= 0x303E) ||
      (cp >= 0x3041 && cp <= 0x33FF) ||
      (cp >= 0x3400 && cp <= 0x4DBF) ||
      (cp >= 0x4E00 && cp <= 0x9FFF) ||
      (cp >= 0xA000 && cp <= 0xA4CF) ||
      (cp >= 0xAC00 && cp <= 0xD7A3) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0xFE30 && cp <= 0xFE4F) ||
      (cp >= 0xFF00 && cp <= 0xFF60) ||
      (cp >= 0xFFE0 && cp <= 0xFFE6) ||
      (cp >= 0x1F300 && cp <= 0x1F64F) ||
      (cp >= 0x1F900 && cp <= 0x1F9FF) ||
      (cp >= 0x20000 && cp <= 0x3FFFD)
    w = w + (if wide { 2 } else { 1 })
  }
  w
}
