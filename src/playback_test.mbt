///| 再生スケジュール（parse_to_playback）のテスト。1 スロット = 1 拍。

///|
/// 基本: key C の 1 は C メジャートライアド + ベース C2
test "playback basic chord" {
  let json = @chord_language.parse_to_playback("1", "C")
  // ベース 36(C2) + 60(C4) 64(E4) 67(G4)
  assert_true(json.contains("\"notes\":[36,60,64,67]"))
  assert_true(json.contains("\"tempo\":100"))
  assert_true(json.contains("\"totalBeats\":4")) // 1 スロット = 4 拍
}

///|
/// _ は直前の発音を持続（dur が伸びる）、% は再打鍵（イベントが増える）
test "playback sustain and repeat" {
  // 1 _ _ _ → イベント1つ dur 16（4 スロット × 4 拍）
  let json = @chord_language.parse_to_playback("1 _ _ _", "C")
  assert_true(json.contains("\"dur\":16"))
  assert_true(json.contains("\"totalBeats\":16"))
  // 1 % → 同じ音のイベント2つ
  let json2 = @chord_language.parse_to_playback("1 %", "C")
  let hits = json2.split("\"notes\":[36,60,64,67]").to_array().length() - 1
  assert_eq(hits, 2)
}

///|
/// N.C. は無音の 1 拍で、_ の持続は N.C. をまたがない
test "playback nc silence" {
  let json = @chord_language.parse_to_playback("NC 1", "C")
  assert_true(json.contains("\"totalBeats\":8"))
  // 最初のイベントは beat 4 から
  assert_true(json.contains("\"beat\":4"))
  // NC _ → イベントなしの 2 拍
  let json2 = @chord_language.parse_to_playback("NC _", "C")
  assert_true(json2.contains("\"events\":[]"))
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
  // key G の 1 → G2 ベース + G4 B4 D5 = 43, 67, 71, 74
  let json = @chord_language.parse_to_playback("1", "G")
  assert_true(json.contains("\"notes\":[43,67,71,74]"))
  // 5(b9) @ C → ルート G(67)、b9 = 67+13 = 80
  let json2 = @chord_language.parse_to_playback("5(b9)", "C")
  assert_true(json2.contains("80"))
  // 1sus4 @ C → 3度(64)ではなく4度(65)
  let json3 = @chord_language.parse_to_playback("1sus4", "C")
  assert_true(json3.contains("65"))
  assert_true(!json3.contains("64"))
  // 1/3 @ C → ベースは E2(40)
  let json4 = @chord_language.parse_to_playback("1/3", "C")
  assert_true(json4.contains("\"notes\":[40,60,64,67]"))
}

///|
/// tempo はフロントマターから、カーソルはセル番号つき
test "playback tempo and cursor" {
  let json = @chord_language.parse_to_playback(
    "---\ntempo: 132\n---\n1 | 4", "C",
  )
  assert_true(json.contains("\"tempo\":132"))
  // カーソル: cell 0 と cell 1（小節線はセルにならない）
  assert_true(json.contains("\"cell\":0"))
  assert_true(json.contains("\"cell\":1"))
}
