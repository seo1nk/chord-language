///| 再生スケジュール（parse_to_playback）のテスト。1 スロット = 1 小節。

///|
/// 基本: key C の 1 は C メジャートライアド + ベース C2
test "playback basic chord" {
  let json = @chord_language.parse_to_playback("1", "C")
  // 上声 60(C4) 64(E4) 67(G4)、ベースは別トラックで拍ごとに刻む。
  // C のベースは C2(36) だと低すぎて小さく聞こえるためオクターブ上の C3(48)
  assert_true(json.contains("\"notes\":[60,64,67]"))
  assert_true(json.contains("\"note\":48"))
  // 4/4 なら 1 スロットでベース 4 打（beat 3 の刻みがある）
  assert_true(json.contains("\"beat\":3,\"dur\":1,\"note\":48"))
  assert_true(json.contains("\"bpm\":120")) // 既定 BPM は 120
  assert_true(json.contains("\"totalBeats\":4")) // 1 スロット = 1 小節（4/4 = 4 拍）
}

///|
/// _ は直前の発音を持続（dur が伸びる）、% は再打鍵（イベントが増える）
test "playback sustain and repeat" {
  // 1 _ _ _ → イベント1つ dur 16（4 スロット × 4 拍）
  let json = @chord_language.parse_to_playback("1 _ _ _", "C")
  assert_true(json.contains("\"dur\":16"))
  assert_true(json.contains("\"totalBeats\":16"))
  // 1 % → 同じ上声のイベント2つ
  let json2 = @chord_language.parse_to_playback("1 %", "C")
  let hits = json2.split("\"notes\":[60,64,67]").to_array().length() - 1
  assert_eq(hits, 2)
}

///|
/// N.C. は無音の 1 拍で、_ の持続は N.C. をまたがない
test "playback nc silence" {
  let json = @chord_language.parse_to_playback("NC 1", "C")
  assert_true(json.contains("\"totalBeats\":8"))
  // 最初のイベントは beat 4 から
  assert_true(json.contains("\"beat\":4"))
  // NC _ → イベントなしの 2 スロット（ベースも無音）
  let json2 = @chord_language.parse_to_playback("NC _", "C")
  assert_true(json2.contains("\"events\":[]"))
  assert_true(json2.contains("\"bass\":[]"))
}

///|
/// グループは等分割（2-5 → 0.5 拍ずつ）
test "playback group subdivision" {
  let json = @chord_language.parse_to_playback("2-5", "C")
  assert_true(json.contains("\"beat\":2"))
  assert_true(json.contains("\"dur\":2"))
  assert_true(json.contains("\"totalBeats\":4"))
}

///|
/// キー変換・テンション・sus・スラッシュベースの音
test "playback voicing details" {
  // key G の 1 → 上声 G4 B4 D5 = 67, 71, 74、ベース G2 = 43（窓内なのでそのまま）
  let json = @chord_language.parse_to_playback("1", "G")
  assert_true(json.contains("\"notes\":[67,71,74]"))
  assert_true(json.contains("\"note\":43"))
  // key Eb の 6（ピッチクラス C）は C2 ではなく C3(48) に持ち上がる
  let json_eb = @chord_language.parse_to_playback("6m7", "Eb")
  assert_true(json_eb.contains("\"note\":48"))
  // 5(b9) @ C → ルート G(67)、b9 = 67+13 = 80
  let json2 = @chord_language.parse_to_playback("5(b9)", "C")
  assert_true(json2.contains("80"))
  // 1sus4 @ C → 3度(64)ではなく4度(65)
  let json3 = @chord_language.parse_to_playback("1sus4", "C")
  assert_true(json3.contains("65"))
  assert_true(!json3.contains("64"))
  // 1/3 @ C → ベースは E2(40)（窓の下端ちょうど）、上声はそのまま
  let json4 = @chord_language.parse_to_playback("1/3", "C")
  assert_true(json4.contains("\"note\":40"))
  assert_true(json4.contains("\"notes\":[60,64,67]"))
}

///|
/// bpm はフロントマターから、カーソルはセル番号つき
test "playback bpm and cursor" {
  let json = @chord_language.parse_to_playback("---\nbpm: 132\n---\n1 | 4", "C")
  assert_true(json.contains("\"bpm\":132"))
  // カーソル: cell 0 と cell 1（小節線はセルにならない）
  assert_true(json.contains("\"cell\":0"))
  assert_true(json.contains("\"cell\":1"))
}

///|
/// 拍子: スロット長とベースの刻みが変わる
test "playback time signatures" {
  // 3/4 → 1 スロット 3 拍、ベース 3 打
  let json = @chord_language.parse_to_playback("---\ntime: 3/4\n---\n1", "C")
  assert_true(json.contains("\"totalBeats\":3"))
  assert_true(json.contains("\"beat\":2,\"dur\":1,\"note\":48"))
  assert_true(!json.contains("\"beat\":3,\"dur\":1,\"note\":48"))
  // 6/8 → 1 スロット 3 拍（4分音符換算）、付点4分グループ × 2 の「ずん・ちゃ・ちゃ」:
  // ベースは強拍のルートのみ、弱拍の 8 分 2 つは上声和音のスタブ
  let json2 = @chord_language.parse_to_playback("---\ntime: 6/8\n---\n1", "C")
  assert_true(json2.contains("\"totalBeats\":3"))
  assert_true(json2.contains("\"beat\":0,\"dur\":0.5,\"note\":48,\"gain\":1"))
  assert_true(json2.contains("\"beat\":1.5,\"dur\":0.5,\"note\":48,\"gain\":1"))
  assert_true(!json2.contains("\"beat\":0.5,\"dur\":0.5,\"note\"")) // 弱拍にベースは無い
  assert_true(
    json2.contains("\"beat\":0.5,\"dur\":0.5,\"notes\":[60,64,67]") &&
    json2.contains("\"beat\":1,\"dur\":0.5,\"notes\":[60,64,67]") &&
    json2.contains("\"beat\":2.5,\"dur\":0.5,\"notes\":[60,64,67]"),
  )
  // 単純拍子では stabs は空
  assert_true(json.contains("\"stabs\":[]"))
  // 2/2 → 1 スロット 4 拍、ベースは 2 分 × 2
  let json3 = @chord_language.parse_to_playback("---\ntime: 2/2\n---\n1", "C")
  assert_true(json3.contains("\"totalBeats\":4"))
  assert_true(json3.contains("\"dur\":2,\"note\":48"))
}

///|
/// bpm フィールドの反映
test "playback bpm field" {
  let json = @chord_language.parse_to_playback("---\nbpm: 132\n---\n1", "C")
  assert_true(json.contains("\"bpm\":132"))
}

///|
/// q(4度堆積)は完全4度を 2 つ積む(root, +5, +10)
test "playback quartal chord" {
  let json = @chord_language.parse_to_playback("1q", "C")
  // C4(60) F4(65) B♭4(70)
  assert_true(json.contains("\"notes\":[60,65,70]"))
}

///|
/// m7-5(ハーフディミニッシュ)は m7b5 と同じ構成音
test "playback half-diminished dash notation" {
  let json = @chord_language.parse_to_playback("2m7-5", "C")
  // D4(62) F4(65) A♭4(68) C5(72)
  assert_true(json.contains("\"notes\":[62,65,68,72]"))
  let json2 = @chord_language.parse_to_playback("2m7b5", "C")
  assert_eq(
    json.contains("\"notes\":[62,65,68,72]"),
    json2.contains("\"notes\":[62,65,68,72]"),
  )
}

///|
/// 転調: 以降のスロットが新キー基準になり、時間・セル番号は不変
test "playback key changes" {
  // [key: +2] 以降は D 基準（1 → D F# A = 62,66,69）。時間は消費しない
  let json = @chord_language.parse_to_playback("1\n[key: +2]\n1", "C")
  assert_true(json.contains("\"notes\":[60,64,67]"))
  assert_true(json.contains("\"notes\":[62,66,69]"))
  assert_true(json.contains("\"totalBeats\":8"))
  // % は転調をまたいでも直前の響き（実音固定）
  let json2 = @chord_language.parse_to_playback("| 1 [key: +2] % |", "C")
  let hits = json2.split("\"notes\":[60,64,67]").to_array().length() - 1
  assert_eq(hits, 2)
  // 絶対キー指定にもプルダウンの δ が一様に適用される（宣言 C・選択 D で [key: F] → G）
  let json3 = @chord_language.parse_to_playback(
    "---\nkey: C\n---\n1\n[key: F]\n1", "D",
  )
  assert_true(json3.contains("\"notes\":[62,66,69]")) // D
  assert_true(json3.contains("\"notes\":[67,71,74]")) // G
  // インライン転調を含む行が別エラーで除外されると、以降は指示なしとして継続
  let json4 = @chord_language.parse_to_playback("1\n[key: +2] 8x\n1", "C")
  assert_true(!json4.contains("\"notes\":[62,66,69]"))
  // totalBeats・cursor のセル数は転調指示の有無で不変
  let with_mod = @chord_language.parse_to_playback(
    "| 1 4 | [key: +2] 5 1 |", "C",
  )
  let without = @chord_language.parse_to_playback("| 1 4 | 5 1 |", "C")
  assert_true(with_mod.contains("\"totalBeats\":16"))
  assert_true(without.contains("\"totalBeats\":16"))
  let count_cells = fn(s : String) {
    s.split("\"cell\":").to_array().length() - 1
  }
  assert_eq(count_cells(with_mod), count_cells(without))
  // 行頭の転調指示は先頭小節線の leading 判定に対して透明
  // （[key: +2] || 1 と || 1 でセル数・拍数が変わらない）
  let with_lead = @chord_language.parse_to_playback("[key: +2] || 1", "C")
  let without_lead = @chord_language.parse_to_playback("|| 1", "C")
  assert_eq(count_cells(with_lead), count_cells(without_lead))
}
