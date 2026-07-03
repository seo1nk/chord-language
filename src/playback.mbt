///|
/// 再生スケジュール生成（仕様 v1.6）。
///
/// 拍の解釈は「1 スロット = 1 拍」:
/// - コード = 1 拍で発音
/// - グループ（2-5）= スロットを等分割して順に発音
/// - `%` = 直前のコードを再打鍵、`_` = 直前の発音を持続（伸ばす）、N.C. = 無音
/// - 小節線・セクション・歌詞は時間に影響しない
///
/// 音楽的な計算（ディグリー→MIDI・% の解決・スケジュール）はすべてここ（MoonBit 側）で行い、
/// JS ランタイムは Web Audio の発音とカーソル表示だけを担当する（単一ソース原則）。

///|
/// 再生イベント（発音単位）
priv struct PlayEvent {
  beat : Double
  mut dur : Double
  notes : Array[Int] // MIDI ノート番号（ベース音を含む）
}

///|
/// カーソルエントリ（スロット単位のハイライト用）
priv struct CursorEntry {
  beat : Double
  dur : Double
  cell : Int // 描画セル（.chord-cell）の文書順インデックス
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
/// ChordNode を MIDI ノート番号列に変換する（ベース音を含む・重複除去済み・昇順）。
/// テンションも鳴らす（v1.6 仕様決定）。
fn chord_midi_notes(node : ChordNode, tonic_pc : Int) -> Array[Int] {
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
  let notes : Array[Int] = [36 + bass_pc]
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
  deduped
}

///|
/// 入力をパースし、指定キーでの再生スケジュールを JSON で返す。
///
/// 返り値: { "tempo": BPM, "totalBeats": 拍数,
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
  let tempo = match result.score.meta {
    Some(meta) =>
      match meta.tempo {
        Some(t) => t
        None => 100
      }
    None => 100
  }
  let events : Array[PlayEvent] = []
  let cursor : Array[CursorEntry] = []
  let mut beat = 0.0
  let mut cell = 0
  // 直前の発音（% の再打鍵と _ の持続に使う）
  let mut last_notes : Array[Int]? = None
  let mut last_event : Int? = None
  for line in result.score.lines {
    let (_, slots, _) = line_slots(line.tokens)
    for slot in slots {
      match slot {
        ChordSlot(node, _) => {
          let notes = chord_midi_notes(node, tonic_pc)
          events.push({ beat, dur: 1.0, notes })
          last_notes = Some(notes)
          last_event = Some(events.length() - 1)
          cursor.push({ beat, dur: 1.0, cell })
          beat = beat + 1.0
        }
        GroupSlot(nodes, _) => {
          let sub = 1.0 / nodes.length().to_double()
          for i, node in nodes {
            let notes = chord_midi_notes(node, tonic_pc)
            events.push({ beat: beat + i.to_double() * sub, dur: sub, notes })
            last_notes = Some(notes)
            last_event = Some(events.length() - 1)
          }
          cursor.push({ beat, dur: 1.0, cell })
          beat = beat + 1.0
        }
        RepeatSlot(_) => {
          match last_notes {
            Some(notes) => {
              events.push({ beat, dur: 1.0, notes })
              last_event = Some(events.length() - 1)
            }
            None => () // 直前のコードが無い % は無音
          }
          cursor.push({ beat, dur: 1.0, cell })
          beat = beat + 1.0
        }
        NcSlot(_) => {
          // 無音の 1 拍。_ の持続は N.C. をまたがない
          last_event = None
          cursor.push({ beat, dur: 1.0, cell })
          beat = beat + 1.0
        }
        BlankSlot(_) => {
          match last_event {
            Some(i) => events[i].dur = events[i].dur + 1.0
            None => ()
          }
          cursor.push({ beat, dur: 1.0, cell })
          beat = beat + 1.0
        }
        EmptySlot(_) => () // || の空セルは時間を持たない（セル番号だけ進む）
      }
      cell = cell + 1
    }
  }
  let obj : Map[String, Json] = {}
  obj["tempo"] = Json::number(tempo.to_double())
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
