///|
/// 再生スケジュール生成。
///
/// 拍の解釈は「1 スロット = 1 小節」。小節の長さは拍子（time、既定 4/4）で決まる:
/// - コード = 上声を 1 小節持続、ベース音は拍ごとに刻む（連打）
/// - グループ（2-5）= 小節を等分割して順に発音
/// - `%` = 直前のコードを再打鍵、`_` = 直前の発音を持続（ベースの刻みは継続）、N.C. = 無音
/// - 8 分系の複合拍子（6/8, 9/8, 12/8, 3/8）のベースは付点 4 分ごとの
///   「ずん・ちゃ・ちゃ」（強拍にルート、続く 8 分 2 つはオクターブ上を弱く）
/// - 小節線・セクション・歌詞は時間に影響しない。bpm は 4 分音符基準
///
/// 音楽的な計算（ディグリー→MIDI・% の解決・スケジュール）はすべてここ（MoonBit 側）で行い、
/// JS ランタイムは Web Audio の発音とカーソル表示だけを担当する（単一ソース原則）。

///|
/// 再生イベント（上声の発音単位）
priv struct PlayEvent {
  beat : Double
  mut dur : Double
  notes : Array[Int] // 上声の MIDI ノート番号（ベースは別トラック）
  bass : Int // ベース音の MIDI ノート番号
  pulse : Bool // ベースを拍ごとに刻むか（グループの細分は単発）
}

///|
/// カーソルエントリ（スロット単位のハイライト用）
priv struct CursorEntry {
  beat : Double
  dur : Double
  cell : Int // 描画セル（.chord-cell）の文書順インデックス
}

///|
/// ベーストラックの 1 打
priv struct BassHit {
  beat : Double
  dur : Double
  note : Int
  gain : Double // 相対音量（強拍 1.0 / 弱拍 0.5）
}

///|
/// ディグリーのメジャースケール上の半音インターバル
fn degree_interval(d : Degree) -> Int {
  match d {
    D1 => 0
    D2 => 2
    D3 => 4
    D4 => 5
    D5 => 7
    D6 => 9
    D7 => 11
  }
}

///|
/// AddDegree のルートからの半音インターバル
fn add_degree_interval(d : AddDegree) -> Int {
  match d {
    D2 => 2
    D4 => 5
    D6 => 9
    D9 => 14
    D11 => 17
    D13 => 21
  }
}

///|
/// ChordNode を (ベース音, 上声ノート列) に変換する（上声は重複除去済み・昇順）。
/// テンションも鳴らす。
fn chord_midi_notes(node : ChordNode, tonic_pc : Int) -> (Int, Array[Int]) {
  let acc = match node.accidental {
    Some(Sharp) => 1
    Some(Flat) => -1
    None => 0
  }
  let root_pc = (tonic_pc + degree_interval(node.degree) + acc + 24) % 12
  let root = 60 + root_pc // C4 基準
  // 基本形
  let mut third = match node.quality {
    Some(Minor) | Some(Diminish) => 3
    _ => 4
  }
  let mut fifth = match node.quality {
    Some(Diminish) => 6
    Some(Augment) => 8
    _ => 7
  }
  let mut has_third = true
  let intervals : Array[Int] = []

  // sus（括弧外・括弧内とも）は 3 度を置換、b5 は 5 度を変化
  let apply_alteration = fn(a : Alteration) {
    match a {
      FlatFive => fifth = 6
      Sus(d) => {
        has_third = false
        third = degree_interval(d)
      }
    }
  }
  match node.alteration {
    Some(a) => apply_alteration(a)
    None => ()
  }
  for opt in node.options {
    match opt {
      AlterationOpt(a) => apply_alteration(a)
      TensionOpt(t) =>
        intervals.push(
          match t {
            FlatNine => 13
            Nine => 14
            SharpNine => 15
            Eleven => 17
            SharpEleven => 18
            FlatThirteen => 20
            Thirteen => 21
          },
        )
    }
  }
  intervals.push(0)
  if has_third {
    intervals.push(third)
  } else {
    intervals.push(third) // sus 音
  }
  intervals.push(fifth)
  match node.seventh {
    Some(Seventh) => intervals.push(10)
    Some(MajorSeventh) => intervals.push(11)
    Some(Sixth) => intervals.push(9)
    Some(Add(d)) => intervals.push(add_degree_interval(d))
    None => ()
  }

  // ベース音（スラッシュ指定 or ルート）を低音域（C2-B2）に
  let bass_pc = match node.bass {
    Some(b) => {
      let b_acc = match b.accidental {
        Some(Sharp) => 1
        Some(Flat) => -1
        None => 0
      }
      (tonic_pc + degree_interval(b.degree) + b_acc + 24) % 12
    }
    None => root_pc
  }
  // ベースは可聴性のため E2(MIDI 40)〜E♭3(51) の窓に収める。
  // 低すぎる音（C2 帯）は三角波では小さく聞こえるためオクターブ上げる
  let mut bass_midi = 36 + bass_pc
  if bass_midi < 40 {
    bass_midi = bass_midi + 12
  }
  let notes : Array[Int] = []
  for i in intervals {
    notes.push(root + i)
  }
  // 重複除去・昇順
  notes.sort()
  let deduped : Array[Int] = []
  for n in notes {
    if deduped.length() == 0 || deduped[deduped.length() - 1] != n {
      deduped.push(n)
    }
  }
  (bass_midi, deduped)
}

///|
/// 入力をパースし、指定キーでの再生スケジュールを JSON で返す。
///
/// 返り値: { "bpm": BPM, "totalBeats": 拍数,
///           "events": [{"beat","dur","notes":[MIDI...]}],
///           "cursor": [{"beat","dur","cell"}] }
/// - key が不正な場合はフロントマターの key（無ければ C）を使う
/// - パースエラーのある行は score から除外済みのため、描画される行だけが鳴る
pub fn parse_to_playback(input : String, key : String) -> String {
  let result = parse(input)
  let key_info = match parse_key_name(key) {
    Some(k) => k
    None =>
      match result.score.meta {
        Some(meta) =>
          match meta.key {
            Some(mk) =>
              match parse_key_name(mk) {
                Some(k) => k
                None => { letter_idx: 0, alter: 0 }
              }
            None => { letter_idx: 0, alter: 0 }
          }
        None => { letter_idx: 0, alter: 0 }
      }
  }
  let tonic_pc = key_pitch_class(key_info)
  let bpm = match result.score.meta {
    Some(meta) =>
      match meta.bpm {
        Some(t) => t
        None => 120
      }
    None => 120
  }
  // 拍子（既定 4/4）から 1 スロット（= 1 小節）の長さとベースの刻みを決める。
  // 長さの単位は 4 分音符（bpm 基準）
  let time_sig = match result.score.meta {
    Some(meta) =>
      match meta.time {
        Some(t) => t
        None => "4/4"
      }
    None => "4/4"
  }
  let (ts_num, ts_den) = match time_sig.find("/") {
    Some(slash) => {
      let n = time_sig.unsafe_substring(start=0, end=slash)
      let d = time_sig.unsafe_substring(start=slash + 1, end=time_sig.length())
      let to_int = fn(x : String) -> Int {
        let mut v = 0
        for c in x {
          v = v * 10 + (c.to_int() - 48)
        }
        v
      }
      (to_int(n), to_int(d))
    }
    None => (4, 4)
  }
  let slot_beats = ts_num.to_double() * 4.0 / ts_den.to_double()
  // ベースの刻み: 8 分系の複合拍子は付点 4 分パルス、それ以外は拍子の 1 拍単位
  let bass_unit = if ts_den == 8 && ts_num % 3 == 0 {
    1.5
  } else {
    4.0 / ts_den.to_double()
  }
  let events : Array[PlayEvent] = []
  let cursor : Array[CursorEntry] = []
  let mut beat = 0.0
  let mut cell = 0
  // 直前の発音（% の再打鍵と _ の持続に使う）
  let mut last_voicing : (Int, Array[Int])? = None
  let mut last_event : Int? = None
  for line in result.score.lines {
    let (_, slots, _) = line_slots(line.tokens)
    for slot in slots {
      match slot {
        ChordSlot(node, _) => {
          let (bass, notes) = chord_midi_notes(node, tonic_pc)
          events.push({ beat, dur: slot_beats, notes, bass, pulse: true })
          last_voicing = Some((bass, notes))
          last_event = Some(events.length() - 1)
          cursor.push({ beat, dur: slot_beats, cell })
          beat = beat + slot_beats
        }
        GroupSlot(nodes, _) => {
          let sub = slot_beats / nodes.length().to_double()
          for i, node in nodes {
            let (bass, notes) = chord_midi_notes(node, tonic_pc)
            events.push({
              beat: beat + i.to_double() * sub,
              dur: sub,
              notes,
              bass,
              pulse: false,
            })
            last_voicing = Some((bass, notes))
            last_event = Some(events.length() - 1)
          }
          cursor.push({ beat, dur: slot_beats, cell })
          beat = beat + slot_beats
        }
        RepeatSlot(_) => {
          match last_voicing {
            Some((bass, notes)) => {
              events.push({ beat, dur: slot_beats, notes, bass, pulse: true })
              last_event = Some(events.length() - 1)
            }
            None => () // 直前のコードが無い % は無音
          }
          cursor.push({ beat, dur: slot_beats, cell })
          beat = beat + slot_beats
        }
        NcSlot(_) => {
          // 無音の 1 スロット。_ の持続は N.C. をまたがない
          last_event = None
          cursor.push({ beat, dur: slot_beats, cell })
          beat = beat + slot_beats
        }
        BlankSlot(_) => {
          match last_event {
            Some(i) => events[i].dur = events[i].dur + slot_beats
            None => ()
          }
          cursor.push({ beat, dur: slot_beats, cell })
          beat = beat + slot_beats
        }
        EmptySlot(_) => () // || の空セルは時間を持たない（セル番号だけ進む）
      }
      cell = cell + 1
    }
  }
  // ベーストラック: 拍ごとの刻み（pulse イベント）またはグループ細分の単発。
  // 複合拍子は付点 4 分のグループを「ずん・ちゃ・ちゃ」に展開する
  let compound = ts_den == 8 && ts_num % 3 == 0
  let bass_hits : Array[BassHit] = []
  let push_hits = fn(start : Double, span : Double, note : Int) {
    if compound {
      // ずん: グループ頭にルートを強く
      let zun_d = if span < 0.5 { span } else { 0.5 }
      bass_hits.push({ beat: start, dur: zun_d, note, gain: 1.0 })
      // ちゃっちゃ: 続く 8 分 2 つはオクターブ上を弱く（グループ内に収まる分だけ）
      for k in 1..=2 {
        let off = 0.5 * k.to_double()
        if off < span - 0.0001 {
          let remain = span - off
          let d = if remain < 0.5 { remain } else { 0.5 }
          bass_hits.push({ beat: start + off, dur: d, note: note + 12, gain: 0.5 })
        }
      }
    } else {
      bass_hits.push({ beat: start, dur: span, note, gain: 1.0 })
    }
  }
  for ev in events {
    if ev.pulse {
      let mut t = ev.beat
      while t < ev.beat + ev.dur - 0.0001 {
        let remain = ev.beat + ev.dur - t
        let d = if bass_unit < remain { bass_unit } else { remain }
        push_hits(t, d, ev.bass)
        t = t + bass_unit
      }
    } else {
      let d = if bass_unit < ev.dur { bass_unit } else { ev.dur }
      push_hits(ev.beat, d, ev.bass)
    }
  }
  let obj : Map[String, Json] = {}
  obj["bpm"] = Json::number(bpm.to_double())
  obj["totalBeats"] = Json::number(beat)
  obj["events"] = Json::array(
    events.map(fn(ev) {
      let e : Map[String, Json] = {}
      e["beat"] = Json::number(ev.beat)
      e["dur"] = Json::number(ev.dur)
      e["notes"] = Json::array(
        ev.notes.map(fn(n) { Json::number(n.to_double()) }),
      )
      Json::object(e)
    }),
  )
  obj["bass"] = Json::array(
    bass_hits.map(fn(b) {
      let e : Map[String, Json] = {}
      e["beat"] = Json::number(b.beat)
      e["dur"] = Json::number(b.dur)
      e["note"] = Json::number(b.note.to_double())
      e["gain"] = Json::number(b.gain)
      Json::object(e)
    }),
  )
  obj["cursor"] = Json::array(
    cursor.map(fn(c) {
      let e : Map[String, Json] = {}
      e["beat"] = Json::number(c.beat)
      e["dur"] = Json::number(c.dur)
      e["cell"] = Json::number(c.cell.to_double())
      Json::object(e)
    }),
  )
  Json::object(obj).stringify()
}
