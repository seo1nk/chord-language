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
  // ダブル以上のアクシデンタルは理論綴りのままだと読めない
  // （Db の b6 = B♭♭ など）ので、正準 12 キー表の異名同音で
  // 単純な綴りに直す（B♭♭ → A）。シングルまでは理論綴りを保つ
  if alt > 1 || alt < -1 {
    let simple = canonical_key_info(letter_semitone(letter) + alt)
    return letter_name(simple.letter_idx) + alter_display(simple.alter)
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

///|
/// KeyInfo をキー名（"C" "F#" "Bb" など）に戻す（表示用）
fn key_info_name(key : KeyInfo) -> String {
  let alter_str = match key.alter {
    1 => "#"
    -1 => "b"
    0 => ""
    n => if n > 0 { "#".repeat(n) } else { "b".repeat(-n) }
  }
  letter_name(key.letter_idx) + alter_str
}

///|
/// 正準 12 キー表（ピッチクラス 0-11 → キー名）。
/// キープルダウンの一覧（widget_keys）と、相対転調・移調後の絶対キーの
/// スペリングの**単一ソース**（表記は一般的なジャズチャート流儀:
/// フラット側は Db/Eb/Ab/Bb、F#/Gb はシャープ側を採用。二重定義しないこと）
fn canonical_key_names() -> Array[String] {
  ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
}

///|
/// ピッチクラスを正準 12 キー表のキーに解決する
fn canonical_key_info(pc : Int) -> KeyInfo {
  match parse_key_name(canonical_key_names()[(pc % 12 + 12) % 12]) {
    Some(k) => k
    None => { letter_idx: 0, alter: 0 } // 正準表は常にパース可能（保険）
  }
}

///|
/// 文書順の転調（[key: 値]）を畳み込むキーカーソル。
/// - current: 現在の実効キー（実音スペリングの基準）
/// - delta: キープルダウンによる移調量（半音）。プルダウンは「初期キーの
///   差し替え」であり、文中の絶対キー指定にも一様に適用する。
///   不変量: pc(実効キー) ≡ pc(ソース上のキー) + delta（転調幅は保存される）
priv struct KeyCursor {
  mut current : KeyInfo
  delta : Int
}

///|
/// 初期キー（プルダウンの選択キー）と宣言キー（フロントマター）からカーソルを作る
fn KeyCursor::make(selected : KeyInfo, declared : KeyInfo) -> KeyCursor {
  let delta = (
      (key_pitch_class(selected) - key_pitch_class(declared)) % 12 + 12
    ) %
    12
  { current: selected, delta }
}

///|
/// 転調指示を 1 つ適用して実効キーを進める。
/// - 相対: 現在の実効キーに半音数を合成し、正準 12 キー表で綴る
/// - 絶対: ソースのキーに delta を適用する。delta = 0 なら原文の綴りを尊重し、
///   移調時（delta ≠ 0）は正準 12 キー表で綴る
fn KeyCursor::apply(self : KeyCursor, change : KeyChange) -> Unit {
  match change {
    RelativeKey(n) =>
      self.current = canonical_key_info(key_pitch_class(self.current) + n + 12)
    AbsoluteKey(name) =>
      match parse_key_name(name) {
        Some(src) =>
          if self.delta == 0 {
            self.current = src
          } else {
            self.current = canonical_key_info(key_pitch_class(src) + self.delta)
          }
        None => () // 検証済みの絶対キーのみ AST に載るため到達しない
      }
  }
}

///|
/// ピッチクラスに転調指示を 1 つ適用する（再生用。スペリングは扱わない）。
/// delta はキープルダウンの移調量で、絶対キー指定にも一様に適用する
fn apply_key_change_pc(pc : Int, delta : Int, change : KeyChange) -> Int {
  match change {
    RelativeKey(n) => ((pc + n) % 12 + 12) % 12
    AbsoluteKey(name) =>
      match parse_key_name(name) {
        Some(k) => (key_pitch_class(k) + delta) % 12
        None => pc // 検証済みの絶対キーのみ AST に載るため到達しない
      }
  }
}
