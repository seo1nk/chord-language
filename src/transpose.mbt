///|
/// ディグリー + キー → 実音コード名の変換（表示用の純関数群）。
///
/// 参照実装: tonal.js `Progression.fromRomanNumerals` / ChordSheetJS `toChordSymbol(key)`。
/// メジャースケール上の音度をレター（C-B）とオルタレーションで解決するため、
/// 異名同音のスペリングが正しくなる（例: key F# の 7 は E#、key Bb の b3 は D♭）。
///
/// 短調（`key: Am`。v1.5）: ディグリーは**主音から数えた長音階の度数**のまま
/// （長調と同じ）。短調だから意味が変わる数字はない。Am なら 1 = A、b3 = C、
/// b6 = F、b7 = G。主音の綴りから同じ規則で解決する（key C#m の b6 は A）。

///|
/// 実音キー
priv struct KeyInfo {
  letter_idx : Int // 0=C, 1=D, 2=E, 3=F, 4=G, 5=A, 6=B
  alter : Int // # = +1, b = -1
  minor : Bool // 短調（キー名の末尾の m）
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
/// キー名（"C" | "F#" | "Bb" | 短調は末尾に m: "Am" "C#m" "Bbm"）をパースする。
/// キーの検証（フロントマター・転調指示）もこの関数で行う
fn parse_key_name(key : String) -> KeyInfo? {
  let all = key.to_array()
  let minor = all.length() >= 2 && all[all.length() - 1] == 'm'
  let chars = if minor { all[0:all.length() - 1].to_owned() } else { all }
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
  Some({ letter_idx, alter, minor })
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
  // 単純な綴りに直す（B♭♭ → A）。シングルまでは理論綴りを保つ。
  // 黒鍵に落ちる場合の綴りはキーの綴り優先度に従う
  if alt > 1 || alt < -1 {
    let simple = canonical_key_info_pref(
      letter_semitone(letter) + alt + 12,
      spelling_pref(key),
    )
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
/// KeyInfo をキー名（"C" "F#" "Bb" "Am" など）に戻す（表示用）
fn key_info_name(key : KeyInfo) -> String {
  let alter_str = match key.alter {
    1 => "#"
    -1 => "b"
    0 => ""
    n => if n > 0 { "#".repeat(n) } else { "b".repeat(-n) }
  }
  letter_name(key.letter_idx) + alter_str + (if key.minor { "m" } else { "" })
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
/// ♯側・♭側に統一した 12 キー表。既定表と綴りが違うキー
/// （C#・Gb など）が選ばれたとき、転調先をその向きで綴るために使う
fn canonical_key_names_sharp() -> Array[String] {
  ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
}

///|
fn canonical_key_names_flat() -> Array[String] {
  ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
}

///|
/// 短調の正準 12 キー表（ピッチクラス 0-11 → キー名）。調号の少ない側の綴り
/// （C#m は 4 つの #、Dbm は 8 つの b になるので C#m。D#m と Ebm は 6 つずつで、
/// よく使われる Ebm）。長調の表と同じく、キープルダウンの一覧と転調先の綴りの単一ソース
fn canonical_minor_key_names() -> Array[String] {
  ["Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "Bbm", "Bm"]
}

///|
fn canonical_minor_key_names_sharp() -> Array[String] {
  ["Cm", "C#m", "Dm", "D#m", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "A#m", "Bm"]
}

///|
fn canonical_minor_key_names_flat() -> Array[String] {
  ["Cm", "Dbm", "Dm", "Ebm", "Em", "Fm", "Gbm", "Gm", "Abm", "Am", "Bbm", "Bm"]
}

///|
/// 長調・短調の正準表（pref の意味は canonical_key_info_pref と同じ）
fn canonical_key_table(minor : Bool, pref : Int) -> Array[String] {
  match (minor, pref) {
    (false, p) if p > 0 => canonical_key_names_sharp()
    (false, p) if p < 0 => canonical_key_names_flat()
    (false, _) => canonical_key_names()
    (true, p) if p > 0 => canonical_minor_key_names_sharp()
    (true, p) if p < 0 => canonical_minor_key_names_flat()
    (true, _) => canonical_minor_key_names()
  }
}

///|
/// 綴り優先度つきで、ピッチクラスを長調・短調の正準キーに解決する（転調先のキー用）
fn canonical_key_info_mode(pc : Int, pref : Int, minor : Bool) -> KeyInfo {
  match parse_key_name(canonical_key_table(minor, pref)[(pc % 12 + 12) % 12]) {
    Some(k) => k
    None => { letter_idx: 0, alter: 0, minor } // 正準表は常にパース可能（保険）
  }
}

///|
/// 綴り優先度つきの正準キー解決（pref > 0 = ♯側、pref < 0 = ♭側、0 = 既定表）。
/// 長調の表を使う（音名の綴り直しにも使う）
fn canonical_key_info_pref(pc : Int, pref : Int) -> KeyInfo {
  canonical_key_info_mode(pc, pref, false)
}

///|
/// 選択キーの綴りから転調先の綴り優先度を導く。既定表と同じ綴りなら 0
/// （従来どおり既定表）、あえて異名同音側を選んだときだけその向きに従う
/// （C# 選択 → ♯側、Gb 選択 → ♭側）
fn spelling_pref(key : KeyInfo) -> Int {
  // 短調は短調の表と比べる（C#m は表どおり = 0、Dbm はあえて ♭ 側 = -1）
  let canonical = canonical_key_info_mode(key_pitch_class(key), 0, key.minor)
  if canonical.letter_idx == key.letter_idx && canonical.alter == key.alter {
    0
  } else if key.alter > 0 {
    1
  } else if key.alter < 0 {
    -1
  } else {
    0
  }
}

///|

///|
/// 文書順の転調（[key: 値]）を畳み込むキーカーソル。
/// - current: 現在の実効キー（実音スペリングの基準）
/// - delta: キープルダウンによる移調量（半音）。プルダウンは「初期キーの
///   差し替え」であり、文中の絶対キー指定にも一様に適用する。
///   不変量: pc(実効キー) ≡ pc(ソース上のキー) + delta（転調幅は保存される）
priv struct KeyCursor {
  mut current : KeyInfo
  delta : Int
  // 転調先の綴り優先度（選択キーの綴りから導出。spelling_pref を参照）
  pref : Int
}

///|
/// 初期キー（プルダウンの選択キー）と宣言キー（フロントマター）からカーソルを作る
fn KeyCursor::make(selected : KeyInfo, declared : KeyInfo) -> KeyCursor {
  let delta = (
      (key_pitch_class(selected) - key_pitch_class(declared)) % 12 + 12
    ) %
    12
  { current: selected, delta, pref: spelling_pref(selected) }
}

///|
/// 転調指示を 1 つ適用して実効キーを進める。
/// - 相対: 現在の実効キーに半音数を合成し、正準 12 キー表で綴る（長調・短調はそのまま）
/// - 絶対: ソースのキーに delta を適用する。delta = 0 なら原文の綴りを尊重し、
///   移調時（delta ≠ 0）は正準 12 キー表で綴る（長調・短調は指示どおり。`[key: C]` で
///   短調から長調へ移れる）
fn KeyCursor::apply(self : KeyCursor, change : KeyChange) -> Unit {
  match change {
    RelativeKey(n) =>
      self.current = canonical_key_info_mode(
        key_pitch_class(self.current) + n + 12,
        self.pref,
        self.current.minor,
      )
    AbsoluteKey(name) =>
      match parse_key_name(name) {
        Some(src) =>
          if self.delta == 0 {
            self.current = src
          } else {
            self.current = canonical_key_info_mode(
              key_pitch_class(src) + self.delta,
              self.pref,
              src.minor,
            )
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
