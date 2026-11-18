///|
/// エディタの色付け用に、コード譜ブロックの字句を「種類と位置」の並びにする(v1.3)。
///
/// 返り値は JSON の配列 `[[行, 開始, 終了, 種類], ...]`:
/// - 行は 1 始まり(エラーの line と同じ)
/// - 開始・終了は行内の文字位置(コードポイント単位、0 始まり、終了は含まない。
///   エラーの position と同じ単位。UTF-16 の位置に直すのは呼び出し側)
/// - 種類は次のいずれか(エディタの CSS クラス名の元になるので、変えるときは互換に注意):
///   fence / meta-key / meta-value(フロントマター)、section / directive、
///   bar / repeat / hold(空拍・空きパート)/ nc / group(グループ区切りの -)、
///   degree(臨時記号 + 度数)/ quality(クオリティ・セブンス・sus など)/
///   tension(括弧の中)/ bass(/ 以降)/ color(@ 以降)、
///   lyric-mark(>)/ lyric / lyric-hold(歌詞の _)/ lyric-split(歌詞の -)
///
/// 字句の区切りはパーサと同じ字句解析(tokenize_line)を使う。正しいかどうかは
/// 見ない(エラーは parse_to_json の errors を別に重ねる)
pub fn highlight_spans(input : String) -> String {
  let spans : Array[Json] = []
  let push = fn(line : Int, start : Int, end : Int, kind : String) {
    if end > start {
      spans.push(
        Json::array([
          Json::number(line.to_double()),
          Json::number(start.to_double()),
          Json::number(end.to_double()),
          Json::string(kind),
        ]),
      )
    }
  }
  let lines = split_lines(input)
  let body_start = highlight_frontmatter(lines, push)
  for idx in body_start..<lines.length() {
    highlight_body_line(lines[idx], idx + 1, push)
  }
  Json::array(spans).stringify()
}

///|
/// フロントマターの行に色を付け、本文の開始行を返す(閉じていなければ色を付けない)
fn highlight_frontmatter(
  lines : Array[String],
  push : (Int, Int, Int, String) -> Unit,
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
    return 0
  }
  for idx in 0..<=close_idx {
    let chars = lines[idx].to_array()
    let (first, last) = content_range(chars)
    if idx == 0 || idx == close_idx {
      push(idx + 1, first, last, "fence")
      continue
    }
    let mut colon = -1
    for i in first..<last {
      if chars[i] == ':' {
        colon = i
        break
      }
    }
    if colon < 0 {
      push(idx + 1, first, last, "meta-key")
    } else {
      push(idx + 1, first, colon, "meta-key")
      let mut v = colon + 1
      while v < last && is_whitespace(chars[v]) {
        v = v + 1
      }
      push(idx + 1, v, last, "meta-value")
    }
  }
  close_idx + 1
}

///|
/// 行の中身の範囲(前後の空白を除く)
fn content_range(chars : Array[Char]) -> (Int, Int) {
  let mut first = 0
  while first < chars.length() && is_whitespace(chars[first]) {
    first = first + 1
  }
  let mut last = chars.length()
  while last > first && is_whitespace(chars[last - 1]) {
    last = last - 1
  }
  (first, last)
}

///|
fn highlight_body_line(
  line : String,
  line_no : Int,
  push : (Int, Int, Int, String) -> Unit,
) -> Unit {
  let chars = line.to_array()
  let (first, last) = content_range(chars)
  if first >= last {
    return
  }
  // 歌詞行
  if chars[first] == '>' {
    push(line_no, first, first + 1, "lyric-mark")
    let mut i = first + 1
    while i < last {
      if is_whitespace(chars[i]) {
        i = i + 1
        continue
      }
      // 歌詞の行の | は区切り(小節線と同じ色。v1.7)
      if chars[i] == '|' {
        push(line_no, i, i + 1, "bar")
        i = i + 1
        continue
      }
      // 断片 1 つ。_ と - は記号として分ける
      let mut run_start = i
      while i < last && !is_whitespace(chars[i]) && chars[i] != '|' {
        let c = chars[i]
        if c == '_' || c == '-' {
          push(line_no, run_start, i, "lyric")
          push(
            line_no,
            i,
            i + 1,
            if c == '_' {
              "lyric-hold"
            } else {
              "lyric-split"
            },
          )
          run_start = i + 1
        }
        i = i + 1
      }
      push(line_no, run_start, i, "lyric")
    }
    return
  }
  // セクションラベル([名前] の単独行。指示は除く)
  if chars[first] == '[' &&
    chars[last - 1] == ']' &&
    last - first >= 2 &&
    !is_directive_inner(chars, first + 1, last) {
    push(line_no, first, last, "section")
    return
  }
  for pt in tokenize_line(line) {
    let end = pt.col + pt.text.to_array().length()
    match pt.kind {
      BarTok => push(line_no, pt.col, end, "bar")
      RepeatTok => push(line_no, pt.col, end, "repeat")
      BlankTok => push(line_no, pt.col, end, "hold")
      DirectiveTok => push(line_no, pt.col, end, "directive")
      ChordTok =>
        if pt.text == "NC" || pt.text == "N.C." {
          push(line_no, pt.col, end, "nc")
        } else {
          highlight_chord_token(pt.text, pt.col, line_no, push)
        }
    }
  }
}

///|
/// コードトークン(グループを含む)を部品に分ける。
/// 1 つのコードとして読めるもの(2m7-5 など)はグループに分けない(パーサと同じ優先順位)
fn highlight_chord_token(
  text : String,
  col : Int,
  line_no : Int,
  push : (Int, Int, Int, String) -> Unit,
) -> Unit {
  let chars = text.to_array()
  let single = match parse_chord(text) {
    Ok(_) => true
    Err(_) => false
  }
  if single {
    highlight_chord_part(chars, 0, chars.length(), col, line_no, push)
    return
  }
  // 括弧の外の - でパートに分ける
  let mut depth = 0
  let mut start = 0
  for i, c in chars {
    if c == '(' {
      depth = depth + 1
    } else if c == ')' && depth > 0 {
      depth = depth - 1
    } else if c == '-' && depth == 0 {
      highlight_chord_part(chars, start, i, col, line_no, push)
      push(line_no, col + i, col + i + 1, "group")
      start = i + 1
    }
  }
  highlight_chord_part(chars, start, chars.length(), col, line_no, push)
}

///|
/// コード記号 1 つ(chars[start..end))を部品に分ける。
/// 臨時記号 + 度数 / クオリティ・セブンスなど / (テンション) / /ベース / @色
fn highlight_chord_part(
  chars : Array[Char],
  start : Int,
  end : Int,
  col : Int,
  line_no : Int,
  push : (Int, Int, Int, String) -> Unit,
) -> Unit {
  if start >= end {
    return
  }
  if end - start == 1 && chars[start] == '_' {
    push(line_no, col + start, col + end, "hold")
    return
  }
  let mut i = start
  // 臨時記号 + 度数
  if i < end && (chars[i] == '#' || chars[i] == 's' || chars[i] == 'b') {
    i = i + 1
  }
  // 度数は 1 桁(57 は 5 + セブンス)
  if i < end && chars[i] >= '0' && chars[i] <= '9' {
    i = i + 1
  }
  push(line_no, col + start, col + i, "degree")
  let degree_end = i
  // 以降は記号で区切られた部品に分ける
  let mut seg = i
  let mut kind = "quality"
  let flush = fn(upto : Int) { push(line_no, col + seg, col + upto, kind) }
  while i < end {
    let c = chars[i]
    if c == '(' && kind != "color" {
      flush(i)
      seg = i
      kind = "tension"
      // 対応する ) まで(閉じていなければ末尾まで)
      let mut depth = 0
      while i < end {
        if chars[i] == '(' {
          depth = depth + 1
        } else if chars[i] == ')' {
          depth = depth - 1
          if depth == 0 {
            i = i + 1
            break
          }
        }
        i = i + 1
      }
      flush(i)
      seg = i
      kind = "quality"
      continue
    }
    // 括弧なしの omit(1omit3。v1.6)も、括弧の中と同じ色にする
    if kind == "quality" &&
      i + 5 <= end &&
      chars[i] == 'o' &&
      chars[i + 1] == 'm' &&
      chars[i + 2] == 'i' &&
      chars[i + 3] == 't' {
      flush(i)
      push(line_no, col + i, col + i + 5, "tension")
      i = i + 5
      seg = i
      continue
    }
    // 括弧なしのテンション(59 / 57b9#11 など)は括弧の中と同じ色にする
    if kind == "quality" {
      let n = bare_tension_length(chars, i, end, degree_end)
      if n > 0 {
        flush(i)
        push(line_no, col + i, col + i + n, "tension")
        i = i + n
        seg = i
        continue
      }
    }
    if c == '/' && kind != "color" {
      flush(i)
      seg = i
      kind = "bass"
    } else if c == '@' {
      flush(i)
      seg = i
      kind = "color"
    }
    i = i + 1
  }
  flush(end)
}

///|
/// chars[i..] が括弧なしのテンション(b9 / 9 / #9 / 11 / #11 / b13 / 13)なら
/// その長さ、そうでなければ 0。`add9` の 9 と、`M9` `maj9`(メジャーセブンスを
/// 補う略記)の 9 はセブンスの一部なので数えない
fn bare_tension_length(
  chars : Array[Char],
  i : Int,
  end : Int,
  degree_end : Int,
) -> Int {
  let mut j = i
  if chars[j] == 'b' || chars[j] == '#' || chars[j] == 's' {
    j = j + 1
  }
  let altered = j > i
  let number = if j < end && chars[j] == '9' {
    1
  } else if j + 1 < end &&
    chars[j] == '1' &&
    (chars[j + 1] == '1' || chars[j + 1] == '3') {
    2
  } else {
    0
  }
  if number == 0 {
    return 0
  }
  // b / # / s が付くのは b9 #9 #11 b13 だけ(b11 #13 はテンションではない)
  if altered {
    let flat = chars[i] == 'b'
    let valid = if number == 1 {
      true
    } else if chars[j + 1] == '1' {
      !flat
    } else {
      flat
    }
    if !valid {
      return 0
    }
  }
  let before = fn(text : String) -> Bool {
    let t = text.to_array()
    let from = i - t.length()
    if from < degree_end {
      return false
    }
    for k, c in t {
      if chars[from + k] != c {
        return false
      }
    }
    true
  }
  if !altered && (before("add") || before("M") || before("maj")) {
    return 0
  }
  j - i + number
}
