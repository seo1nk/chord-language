///|
/// ディグリー + キー → 実音コード名の変換（表示用の純関数群）。
///
/// 参照実装: tonal.js `Progression.fromRomanNumerals` / ChordSheetJS `toChordSymbol(key)`。
/// メジャースケール上の音度をレター（C-B）とオルタレーションで解決するため、
/// 異名同音のスペリングが正しくなる（例: key F# の 7 は E#、key Bb の b3 は D♭）。

///|
/// 実音キー（メジャーのみ）
priv struct KeyInfo {
  letter_idx : Int // 0=C, 1=D, 2=E, 3=F, 4=G, 5=A, 6=B
  alter : Int // # = +1, b = -1
}

///|
fn letter_semitone(idx : Int) -> Int {
  [0, 2, 4, 5, 7, 9, 11][idx]
}

///|
fn letter_name(idx : Int) -> String {
  ["C", "D", "E", "F", "G", "A", "B"][idx]
}

///|
/// キー名（"C" | "F#" | "Bb" など）をパースする。フロントマターで検証済みの値を想定
fn parse_key_name(key : String) -> KeyInfo? {
  let chars = key.to_array()
  if chars.length() < 1 || chars.length() > 2 {
    return None
  }
  let letter_idx = match chars[0] {
    'C' => 0
    'D' => 1
    'E' => 2
    'F' => 3
    'G' => 4
    'A' => 5
    'B' => 6
    _ => return None
  }
  let alter = if chars.length() == 2 {
    match chars[1] {
      '#' => 1
      'b' => -1
      _ => return None
    }
  } else {
    0
  }
  Some({ letter_idx, alter })
}

///|
/// オルタレーション数を表示記号にする（表示は ♭、# はそのまま）
fn alter_display(alter : Int) -> String {
  match alter {
    2 => "##"
    1 => "#"
    0 => ""
    -1 => "♭"
    -2 => "♭♭"
    // 理論上の極端なケース（トリプル以上）はそのまま連結する
    n => if n > 0 { "#".repeat(n) } else { "♭".repeat(-n) }
  }
}

///|
/// キー上のディグリー（+アクシデンタル）を実音名（表示用）に解決する
fn degree_note_name(
  key : KeyInfo,
  degree : Degree,
  accidental : Accidental?,
) -> String {
  let deg_n = match degree {
    D1 => 1
    D2 => 2
    D3 => 3
    D4 => 4
    D5 => 5
    D6 => 6
    D7 => 7
  }
  // メジャースケールの音度インターバル（半音）
  let interval = [0, 2, 4, 5, 7, 9, 11][deg_n - 1]
  let letter = (key.letter_idx + deg_n - 1) % 7
  let tonic_semi = letter_semitone(key.letter_idx) + key.alter
  let target_semi = (tonic_semi + interval + 12) % 12
  let natural = letter_semitone(letter)
  let mut alt = target_semi - natural
  if alt > 6 {
    alt = alt - 12
  }
  if alt < -6 {
    alt = alt + 12
  }
  // DSL のアクシデンタル（b/s）は同じレターの半音変化として適用する
  match accidental {
    Some(Sharp) => alt = alt + 1
    Some(Flat) => alt = alt - 1
    None => ()
  }
  letter_name(letter) + alter_display(alt)
}

///|
/// ChordNode をキーに基づく実音コード名テキスト（表示用）に変換する。
/// クオリティ・セブンス・テンション等はディグリー表示と共通のサフィックス
/// （chord_suffix_text）を使い、ルートとベースだけを実音に解決する
fn chord_note_text(node : ChordNode, key : KeyInfo) -> String {
  let root = degree_note_name(key, node.degree, node.accidental)
  let bass = match node.bass {
    Some(b) => "/" + degree_note_name(key, b.degree, b.accidental)
    None => ""
  }
  root + chord_suffix_text(node) + bass
}

///|
/// キーのピッチクラス（0-11。異名同音の判定に使う）
fn key_pitch_class(key : KeyInfo) -> Int {
  (letter_semitone(key.letter_idx) + key.alter + 12) % 12
}
