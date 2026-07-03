///|
/// 楽譜
pub struct ScoreAST {
  meta : ScoreMeta? // フロントマター（宣言時のみ Some。key 未宣言時の既定値 C は表示層が適用）
  sections : Array[SectionLabel] // セクションラベル（v1.4。行番号順）
  lines : Array[Line]
}

///|
/// セクションラベル（v1.4。`[Aメロ]` のような単独行）
pub struct SectionLabel {
  line_number : Int
  name : String
}

///|
/// フロントマターのメタデータ（v1.2）
pub struct ScoreMeta {
  key : String? // "C" | "G" | "F#" | "Bb" など（メジャーキーのみ）
  tempo : Int? // BPM・4分音符基準（v1.6/v1.7。フィールド名は bpm が正式、tempo は互換。20-400。既定 120）
  time : String? // 拍子（v1.7。"4/4" など。ホワイトリスト制。既定 4/4）
}

///|
/// 楽譜の行
pub struct Line {
  line_number : Int // 元ソースの行番号（1-indexed。空行・コメント行・フロントマターを含めて数える）
  tokens : Array[Token]
  // ペア歌詞行（v1.4）: コード系トークン（Chord/ChordGroup/Repeat）に左から
  // 割り当てられた歌詞断片。None = そのコードには歌詞なし。空配列 = 歌詞行なし
  mut lyrics : Array[String?]
}

///|
/// 行の要素
pub enum Token {
  Chord(ChordNode)
  ChordGroup(Array[ChordNode]) // - で連結された同一スロットのコード列（v1.3）
  BarLine
  Repeat // %（直前のコードの反復。v1.3）
  NoChord // NC / N.C.（コードなし。v1.5）
  EmptyBeat // _（空の拍。スロットを占有し歌詞を割り当てられる。v1.5）
}

///|
/// コード本体のパース
pub struct ChordNode {
  accidental : Accidental?
  degree : Degree
  quality : Quality?
  seventh : Seventh?
  alteration : Alteration? // 括弧外
  options : Array[ChordOption] // 括弧内
  bass : BassNote?
  color : ChordColor? // 強調色（@blue / @red / @green）
}

///|
pub enum Accidental {
  Sharp // s
  Flat // b
}

///|
/// 1-7度
pub enum Degree {
  D1
  D2
  D3
  D4
  D5
  D6
  D7
}

///|
/// コードトーンに追加されるディグリー
pub enum AddDegree {
  D2
  D4
  D6
  D9
  D11
  D13
}

///|
pub enum Quality {
  Minor // m
  Diminish // dim
  Augment // aug
}

///|
pub enum Seventh {
  Add(AddDegree) // add9
  Seventh // 7
  MajorSeventh // M7
  Sixth // 6
}

///|
/// セブンスのあとに引っ付いたりするもの
pub enum Alteration {
  FlatFive // b5
  Sus(Degree) // sus2, sus4, etc.
}

///|
/// カッコ内に書くことがあるもの
pub enum ChordOption {
  TensionOpt(Tension)
  AlterationOpt(Alteration)
}

///|
/// テンション
pub enum Tension {
  FlatNine // b9
  Nine // 9
  SharpNine // s9
  Eleven // 11
  SharpEleven // s11
  FlatThirteen // b13
  Thirteen // 13
}

///|
/// ベース
pub struct BassNote {
  accidental : Accidental?
  degree : Degree
}

///|
/// コードの強調色（ブログ記事中で目立たせたいコードに付ける表示アノテーション）
pub enum ChordColor {
  Blue // @blue
  Red // @red
  Green // @green
}

///|
pub fn Degree::from_char(c : Char) -> Degree? {
  match c {
    '1' => Some(D1)
    '2' => Some(D2)
    '3' => Some(D3)
    '4' => Some(D4)
    '5' => Some(D5)
    '6' => Some(D6)
    '7' => Some(D7)
    _ => None
  }
}

///|
pub fn Degree::to_string(self : Degree) -> String {
  match self {
    D1 => "1"
    D2 => "2"
    D3 => "3"
    D4 => "4"
    D5 => "5"
    D6 => "6"
    D7 => "7"
  }
}

///|
pub fn AddDegree::from_string(s : String) -> AddDegree? {
  match s {
    "2" => Some(D2)
    "4" => Some(D4)
    "6" => Some(D6)
    "9" => Some(D9)
    "11" => Some(D11)
    "13" => Some(D13)
    _ => None
  }
}

///|
pub fn AddDegree::to_string(self : AddDegree) -> String {
  match self {
    D2 => "2"
    D4 => "4"
    D6 => "6"
    D9 => "9"
    D11 => "11"
    D13 => "13"
  }
}

///|
pub fn ChordColor::from_string(s : String) -> ChordColor? {
  match s {
    "blue" => Some(Blue)
    "red" => Some(Red)
    "green" => Some(Green)
    _ => None
  }
}

///|
pub fn ChordColor::to_string(self : ChordColor) -> String {
  match self {
    Blue => "blue"
    Red => "red"
    Green => "green"
  }
}
