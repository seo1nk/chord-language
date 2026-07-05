///| パーサの blackbox テスト。

///| 仕様書 docs/chord.md の構文例・エラー一覧との対応は docs/spec-test-matrix.md を参照。

///|
/// エラーが1件だけ発生することを確認して返すヘルパ
fn single_error(input : String) -> @chord_language.ParseError {
  let r = @chord_language.parse(input)
  if r.errors.length() != 1 {
    abort("expected exactly 1 error for: " + input)
  }
  r.errors[0]
}

///|
/// エラーなしでパースできることを確認して返すヘルパ
fn parse_ok(input : String) -> @chord_language.ScoreAST {
  let r = @chord_language.parse(input)
  if r.errors.length() > 0 {
    abort("unexpected errors for: " + input + " -> " + r.errors[0].to_string())
  }
  r.score
}

///|
/// 基本的なコードのパーステスト
test "parse basic chords" {
  let score = parse_ok("1 3m7 4M7 5")
  assert_eq(score.lines.length(), 1)
  assert_eq(score.lines[0].tokens.length(), 4)
  assert_eq(score.lines[0].line_number, 1)
}

///|
/// バーライン付きのパーステスト
test "parse with barlines" {
  let score = parse_ok("1 3m7 | 4M7 5")
  assert_eq(score.lines[0].tokens.length(), 5) // 4 chords + 1 barline
  match score.lines[0].tokens[2] {
    @chord_language.BarLine => () // OK
    _ => fail("Expected BarLine at position 2")
  }
}

///|
/// 複数行のパーステスト
test "parse multiple lines" {
  let score = parse_ok("1 3m7 4M7 5\nb7 1")
  assert_eq(score.lines.length(), 2)
  assert_eq(score.lines[0].tokens.length(), 4)
  assert_eq(score.lines[1].tokens.length(), 2)
  assert_eq(score.lines[1].line_number, 2)
}

///|
/// 複雑なコードのパーステスト
test "parse complex chords" {
  let score = parse_ok("s4M7(b5,b9,s11) 2m7(b5) 5(b9) 1M7(sus4,9)")
  assert_eq(score.lines[0].tokens.length(), 4)
  match score.lines[0].tokens[0] {
    @chord_language.Chord(node) => {
      match node.accidental {
        Some(@chord_language.Sharp) => () // OK
        _ => fail("Expected Sharp accidental")
      }
      match node.degree {
        @chord_language.D4 => () // OK
        _ => fail("Expected degree 4")
      }
      match node.seventh {
        Some(@chord_language.MajorSeventh) => () // OK
        _ => fail("Expected MajorSeventh")
      }
      assert_eq(node.options.length(), 3)
    }
    _ => fail("Expected Chord token")
  }
}

///|
/// 括弧内の空白を許容する（`1M7(b9, s11)` は 1 トークン）
test "parse options with spaces inside parentheses" {
  let score = parse_ok("1M7(b9, s11) 2m7( b5 )")
  assert_eq(score.lines[0].tokens.length(), 2)
  match score.lines[0].tokens[0] {
    @chord_language.Chord(node) => assert_eq(node.options.length(), 2)
    _ => fail("Expected Chord token")
  }
}

///|
/// # はコメントではなくシャープ記号（s と等価）
test "parse sharp with hash" {
  let score = parse_ok("1 #4 | #1m7 4M7(b9,#11) | 3m/#4")
  assert_eq(score.lines.length(), 1)
  // #4 と s4 は同じ AST になる
  assert_eq(parse_ok("#4").to_json(), parse_ok("s4").to_json())
  // テンション #9 / #11 は s9 / s11 と等価
  assert_eq(parse_ok("1(#9,#11)").to_json(), parse_ok("1(s9,s11)").to_json())
  // スラッシュベースのアクシデンタルにも使える
  assert_eq(parse_ok("3m/#4").to_json(), parse_ok("3m/s4").to_json())
}

///|
/// maj7 は M7 の別表記（同じ AST になる）
test "parse maj7 alias" {
  assert_eq(parse_ok("1maj7").to_json(), parse_ok("1M7").to_json())
  assert_eq(parse_ok("4maj7(b5)/3").to_json(), parse_ok("4M7(b5)/3").to_json())
  // マイナーの m とは衝突しない
  assert_eq(parse_ok("2mmaj7").to_json(), parse_ok("2mM7").to_json())
  // 重複はエラー
  match single_error("1maj7M7").kind {
    @chord_language.DuplicateSeventh => () // OK
    _ => fail("Expected DuplicateSeventh for 1maj7M7")
  }
}

///|
/// 空入力・空白のみの入力は空の楽譜として成功する
test "parse empty input" {
  assert_eq(parse_ok("").lines.length(), 0)
  assert_eq(parse_ok("   \n\t\n").lines.length(), 0)
}

///|
/// 仕様書の成功例: 括弧外オルタレーションと混在記法・セブンス優先順位
test "parse spec success examples" {
  // 括弧外
  let _ = parse_ok("1sus4 4M7b5")
  // 混在（両方保持）
  match parse_ok("1M7b5(b9)").lines[0].tokens[0] {
    @chord_language.Chord(node) => {
      match node.alteration {
        Some(@chord_language.FlatFive) => () // OK
        _ => fail("Expected FlatFive alteration")
      }
      assert_eq(node.options.length(), 1)
    }
    _ => fail("Expected Chord")
  }
  // セブンス優先順位: 17 は Seventh、16 は Sixth
  match parse_ok("17").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.seventh {
        Some(@chord_language.Seventh) => () // OK
        _ => fail("Expected Seventh for 17")
      }
    _ => fail("Expected Chord")
  }
  match parse_ok("16 36").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.seventh {
        Some(@chord_language.Sixth) => () // OK
        _ => fail("Expected Sixth for 16")
      }
    _ => fail("Expected Chord")
  }
  // クオリティ
  match parse_ok("3dim7 2aug").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.quality {
        Some(@chord_language.Diminish) => () // OK
        _ => fail("Expected Diminish")
      }
    _ => fail("Expected Chord")
  }
  // add系
  let score = parse_ok("1add2 1add4 1add6 1add9 3add11 5add13")
  assert_eq(score.lines[0].tokens.length(), 6)
}

///|
/// ベース音付きコードのパーステスト
test "parse chords with bass notes" {
  let score = parse_ok("5/3 b7/5 1M7(b9)/3 1/b3")
  for token in score.lines[0].tokens {
    match token {
      @chord_language.Chord(node) =>
        match node.bass {
          Some(_) => () // OK
          None => fail("Expected bass note")
        }
      _ => fail("Expected Chord token")
    }
  }
  // ベースのアクシデンタル
  match score.lines[0].tokens[3] {
    @chord_language.Chord(node) =>
      match node.bass {
        Some(b) =>
          match b.accidental {
            Some(@chord_language.Flat) => () // OK
            _ => fail("Expected flat bass accidental")
          }
        None => fail("Expected bass")
      }
    _ => fail("Expected Chord")
  }
}

///|
/// エラー収集: 不正な行はスキップされ、正しい行は部分 AST に残る
test "collect errors and keep valid lines" {
  let r = @chord_language.parse("1 3m7\n8x 5\n4M7 1\n1M7() b9x")
  assert_eq(r.errors.length(), 3) // 8x, 1M7(), b9x
  assert_eq(r.score.lines.length(), 2) // 1行目と3行目
  assert_eq(r.score.lines[0].line_number, 1)
  assert_eq(r.score.lines[1].line_number, 3)
  // 全エラーに行番号がある
  for e in r.errors {
    match e.line {
      Some(_) => () // OK
      None => fail("Expected line number on error")
    }
  }
}

///|
/// エラー位置: 行内の 0-indexed 文字位置が入る
test "error positions are line-relative" {
  // "1 8x" -> 8x はカラム2、ディグリーエラーはトークン先頭
  let e1 = single_error("1 8x")
  @debug.assert_eq(e1.position, Some(2))
  @debug.assert_eq(e1.line, Some(1))
  // "1M77" -> セブンス重複はトークン内位置3 (2つ目の7)
  let e2 = single_error("1M77")
  @debug.assert_eq(e2.position, Some(3))
}

///|
/// エラーケース: 不正なディグリー
test "error on invalid degree" {
  match single_error("1 8m7 4M7").kind {
    @chord_language.InvalidDegree(_) => () // OK
    _ => fail("Expected InvalidDegree error")
  }
}

///|
/// エラーケース: セブンスの重複（1M77 / 17M7）
test "error on duplicate seventh" {
  match single_error("1M77").kind {
    @chord_language.DuplicateSeventh => () // OK
    _ => fail("Expected DuplicateSeventh for 1M77")
  }
  match single_error("17M7").kind {
    @chord_language.DuplicateSeventh => () // OK
    _ => fail("Expected DuplicateSeventh for 17M7")
  }
}

///|
/// エラーケース: 空の括弧
test "error on empty parentheses" {
  match single_error("1M7() 3m7").kind {
    @chord_language.EmptyParentheses => () // OK
    _ => fail("Expected EmptyParentheses error")
  }
}

///|
/// エラーケース: 括弧の不一致
test "error on unmatched parenthesis" {
  match single_error("1M7(b9 3m7").kind {
    @chord_language.UnmatchedParenthesis => () // OK
    _ => fail("Expected UnmatchedParenthesis error")
  }
}

///|
/// エラーケース: カンマの不正使用
test "error on invalid comma usage" {
  for input in ["1(,b9)", "1(b9,)", "1(b9,,s11)"] {
    match single_error(input).kind {
      @chord_language.InvalidCommaUsage => () // OK
      _ => fail("Expected InvalidCommaUsage for " + input)
    }
  }
}

///|
/// エラーケース: 不正なテンション
test "error on invalid tension" {
  match single_error("1(b8)").kind {
    @chord_language.InvalidTension(_) => () // OK
    _ => fail("Expected InvalidTension error")
  }
}

///|
/// エラーケース: ベースディグリー欠落と不正ベース度数
test "error on bass degree issues" {
  match single_error("1M7/ 3m7").kind {
    @chord_language.MissingBassDegree => () // OK
    _ => fail("Expected MissingBassDegree error")
  }
  // 1-7 以外の度数は InvalidDegree を伝播
  match single_error("1/8").kind {
    @chord_language.InvalidDegree(_) => () // OK
    _ => fail("Expected InvalidDegree error")
  }
}

///|
/// エラーケース: 不正なsusディグリー（括弧外・括弧内とも）
test "error on invalid sus degree" {
  for input in ["1sus5 3m7", "1(sus11)", "1(sus)", "1(sus5)"] {
    match single_error(input).kind {
      @chord_language.InvalidSusDegree(_) => () // OK
      _ => fail("Expected InvalidSusDegree for " + input)
    }
  }
}

///|
/// 空行を含む入力で行番号が元ソース基準になる
test "line numbers account for blank lines" {
  let e = single_error("1\n\n\n8")
  @debug.assert_eq(e.line, Some(4))
}

///|
/// 色アノテーション: 基本
test "parse chord colors" {
  let score = parse_ok("1@red 3m7@blue 4M7@green 5")
  match score.lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.color {
        Some(@chord_language.Red) => () // OK
        _ => fail("Expected Red")
      }
    _ => fail("Expected Chord")
  }
  match score.lines[0].tokens[1] {
    @chord_language.Chord(node) =>
      match node.color {
        Some(@chord_language.Blue) => () // OK
        _ => fail("Expected Blue")
      }
    _ => fail("Expected Chord")
  }
  match score.lines[0].tokens[2] {
    @chord_language.Chord(node) =>
      match node.color {
        Some(@chord_language.Green) => () // OK
        _ => fail("Expected Green")
      }
    _ => fail("Expected Chord")
  }
  match score.lines[0].tokens[3] {
    @chord_language.Chord(node) =>
      match node.color {
        None => () // OK
        _ => fail("Expected no color")
      }
    _ => fail("Expected Chord")
  }
}

///|
/// 色アノテーション: 複雑なコードとの組み合わせ（末尾位置）
test "parse color on complex chord" {
  match parse_ok("s4M7(b5,b9)/b3@red").lines[0].tokens[0] {
    @chord_language.Chord(node) => {
      match node.color {
        Some(@chord_language.Red) => () // OK
        _ => fail("Expected Red color")
      }
      match node.bass {
        Some(_) => () // OK
        None => fail("Expected bass note")
      }
      assert_eq(node.options.length(), 2)
    }
    _ => fail("Expected Chord token")
  }
}

///|
/// エラーケース: 色関連
test "error on color issues" {
  for input in ["1@yellow 3m7", "1@ 3m7", "1@red/3"] {
    match single_error(input).kind {
      @chord_language.InvalidColor(_) => () // OK
      _ => fail("Expected InvalidColor for " + input)
    }
  }
}

///|
/// フロントマター: key の宣言
test "parse frontmatter with key" {
  let score = parse_ok("---\nkey: G\n---\n1 4 5")
  match score.meta {
    Some(meta) => @debug.assert_eq(meta.key, Some("G"))
    None => fail("Expected meta")
  }
  // 本文の行番号はフロントマター込みで数える
  assert_eq(score.lines[0].line_number, 4)
  // アクシデンタル付きキー
  match parse_ok("---\nkey: F#\n---\n1").meta {
    Some(meta) => @debug.assert_eq(meta.key, Some("F#"))
    None => fail("Expected meta")
  }
  match parse_ok("---\nkey: Bb\n---\n1").meta {
    Some(meta) => @debug.assert_eq(meta.key, Some("Bb"))
    None => fail("Expected meta")
  }
}

///|
/// フロントマター: 省略時は meta なし（既定値 C は表示層が適用）
test "no frontmatter means no meta" {
  match parse_ok("1 4 5").meta {
    None => () // OK
    Some(_) => fail("Expected no meta")
  }
  // key フィールドなしのフロントマターは meta ありの key なし
  match parse_ok("---\n---\n1").meta {
    Some(meta) => @debug.assert_eq(meta.key, None)
    None => fail("Expected meta")
  }
}

///|
/// フロントマター: エラーケース
test "frontmatter errors" {
  // 閉じ --- の欠落
  let r1 = @chord_language.parse("---\nkey: G\n1 4 5")
  assert_eq(r1.errors.length(), 1)
  match r1.errors[0].kind {
    @chord_language.UnclosedFrontmatter => () // OK
    _ => fail("Expected UnclosedFrontmatter")
  }
  // 不正なキー名
  match single_error("---\nkey: H\n---\n1").kind {
    @chord_language.InvalidKey(_) => () // OK
    _ => fail("Expected InvalidKey")
  }
  match single_error("---\nkey: Gm\n---\n1").kind {
    @chord_language.InvalidKey(_) => () // OK
    _ => fail("Expected InvalidKey (minor keys unsupported)")
  }
  // 未知のフィールド
  let e = single_error("---\ncomposer: X\n---\n1")
  match e.kind {
    @chord_language.InvalidFrontmatterField(_) => () // OK
    _ => fail("Expected InvalidFrontmatterField")
  }
  @debug.assert_eq(e.line, Some(2))
  // フロントマターにエラーがあっても本文はパースされる
  let r2 = @chord_language.parse("---\nkey: H\n---\n1 4 5")
  assert_eq(r2.score.lines.length(), 1)
}

///|
/// JSON出力: 基本構造と meta
test "json output" {
  let score = parse_ok("---\nkey: G\n---\n1 3m7")
  let json = score.to_json()
  assert_true(json.contains("ScoreBlock"))
  assert_true(json.contains("\"key\": \"G\""))
  assert_true(json.contains("lines"))
  assert_true(json.contains("Chord"))
}

///|
/// parse_to_json: 構造化エラー（kind/line/position）と部分 AST
test "parse_to_json structured errors" {
  let json = @chord_language.parse_to_json("1 4\n8x 5")
  assert_true(json.contains("\"success\":false"))
  assert_true(json.contains("\"kind\":\"InvalidDegree\""))
  assert_true(json.contains("\"line\":2"))
  assert_true(json.contains("\"position\":0"))
  // 部分 AST (1行目) は data に残る
  assert_true(json.contains("ScoreBlock"))
  let ok_json = @chord_language.parse_to_json("1 4 5")
  assert_true(ok_json.contains("\"success\":true"))
  assert_true(ok_json.contains("\"errors\":[]"))
}

///|
/// 制御文字を含む入力でもエラーJSONが妥当（stringify によるエスケープ）
test "error json escapes control characters" {
  let json = @chord_language.parse_to_json("1\u{01}")
  assert_true(json.contains("\\u0001"))
  assert_true(!json.contains("\u{01}"))
}

///|
/// 仕様書の完全な入力例
test "parse spec example" {
  let score = parse_ok(
    "1 3m7 4M7 5 | b7 1\ns4M7(b5,b9,s11) 5 |\n2m7(b5) 5(b9) 1M7(sus4,9)",
  )
  assert_eq(score.lines.length(), 3)
  assert_eq(score.lines[0].tokens.length(), 7)
  assert_eq(score.lines[1].tokens.length(), 3)
  assert_eq(score.lines[2].tokens.length(), 3)
}

///|
/// 複数スペース・タブのテスト
test "parse with multiple spaces and tabs" {
  let score = parse_ok("1  3m7\t\t4M7   5")
  assert_eq(score.lines[0].tokens.length(), 4)
}

///|
/// テンション網羅: s9 / 11 / b13 / 13（対応表ギャップの回帰テスト）
test "parse all tensions" {
  match parse_ok("1M7(s9,11,b13,13)").lines[0].tokens[0] {
    @chord_language.Chord(node) => {
      assert_eq(node.options.length(), 4)
      match node.options[0] {
        @chord_language.TensionOpt(@chord_language.SharpNine) => () // OK
        _ => fail("Expected s9")
      }
      match node.options[2] {
        @chord_language.TensionOpt(@chord_language.FlatThirteen) => () // OK
        _ => fail("Expected b13")
      }
    }
    _ => fail("Expected Chord")
  }
}

///|
/// 正常系 sus2 / sus6（括弧外・括弧内）
test "parse sus2 and sus6" {
  match parse_ok("1sus2").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.alteration {
        Some(@chord_language.Sus(@chord_language.D2)) => () // OK
        _ => fail("Expected sus2")
      }
    _ => fail("Expected Chord")
  }
  match parse_ok("1(sus6)").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.options[0] {
        @chord_language.AlterationOpt(@chord_language.Sus(@chord_language.D6)) =>
          () // OK
        _ => fail("Expected sus6 option")
      }
    _ => fail("Expected Chord")
  }
}

///|
/// add 系の AST 値検証と、ルート/ベースのアクシデンタル・単独クオリティ
test "parse ast values for add, accidentals, qualities" {
  // add9 の degree
  match parse_ok("1add9").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.seventh {
        Some(@chord_language.Add(@chord_language.D9)) => () // OK
        _ => fail("Expected add9")
      }
    _ => fail("Expected Chord")
  }
  // ルートの Flat
  match parse_ok("b7").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.accidental {
        Some(@chord_language.Flat) => () // OK
        _ => fail("Expected flat root")
      }
    _ => fail("Expected Chord")
  }
  // 単独の 3m（セブンスなし）
  match parse_ok("3m").lines[0].tokens[0] {
    @chord_language.Chord(node) => {
      match node.quality {
        Some(@chord_language.Minor) => () // OK
        _ => fail("Expected minor")
      }
      match node.seventh {
        None => () // OK
        _ => fail("Expected no seventh")
      }
    }
    _ => fail("Expected Chord")
  }
  // aug
  match parse_ok("2aug").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.quality {
        Some(@chord_language.Augment) => () // OK
        _ => fail("Expected augment")
      }
    _ => fail("Expected Chord")
  }
  // ベースの Sharp
  match parse_ok("1/s4").lines[0].tokens[0] {
    @chord_language.Chord(node) =>
      match node.bass {
        Some(b) =>
          match b.accidental {
            Some(@chord_language.Sharp) => () // OK
            _ => fail("Expected sharp bass")
          }
        None => fail("Expected bass")
      }
    _ => fail("Expected Chord")
  }
  // 括弧外 sus + 括弧内の混在
  match parse_ok("2m7sus4(9,s11)").lines[0].tokens[0] {
    @chord_language.Chord(node) => {
      match node.alteration {
        Some(@chord_language.Sus(_)) => () // OK
        _ => fail("Expected sus alteration")
      }
      assert_eq(node.options.length(), 2)
    }
    _ => fail("Expected Chord")
  }
}

///|
/// エラーケース: 不正なセブンス表記
test "error on invalid seventh" {
  match single_error("1add5").kind {
    @chord_language.InvalidSeventh(_) => () // OK
    _ => fail("Expected InvalidSeventh")
  }
}

///|
/// エラーケース: 認識できない文字列
test "error on unrecognized token" {
  for input in ["1x", "1m7x", "1b9)"] {
    match single_error(input).kind {
      @chord_language.UnrecognizedToken(_) => () // OK
      _ => fail("Expected UnrecognizedToken for " + input)
    }
  }
}

///|
/// エラーケース: ルートディグリー欠落（/3 は InvalidDegree）
test "error on missing root degree" {
  match single_error("/3").kind {
    @chord_language.InvalidDegree(_) => () // OK
    _ => fail("Expected InvalidDegree for /3")
  }
}

///|
/// エラーケース: セブンス重複の仕様例（1M7M7 / 1M7add9）
test "error on duplicate seventh spec examples" {
  for input in ["1M7M7", "1M7add9"] {
    match single_error(input).kind {
      @chord_language.DuplicateSeventh => () // OK
      _ => fail("Expected DuplicateSeventh for " + input)
    }
  }
}

///|
/// エラーケース: アクシデンタルのみのベース（1/b）
test "error on bass with accidental only" {
  match single_error("1/b").kind {
    @chord_language.MissingBassDegree => () // OK
    _ => fail("Expected MissingBassDegree for 1/b")
  }
}

///|
/// エラーケース: 色名は小文字のみ
test "error on uppercase color name" {
  match single_error("1@RED").kind {
    @chord_language.InvalidColor(_) => () // OK
    _ => fail("Expected InvalidColor for 1@RED")
  }
}

///|
/// エラーの token フィールドが記録される
test "error records token field" {
  let e = single_error("1 8x")
  match e.token {
    Some(t) => assert_eq(t, "8x")
    None => fail("Expected token field")
  }
}

///|
/// 予約トークンの現行動作の固定（|| は小節線2つ）
test "reserved tokens current behavior" {
  let score = parse_ok("1 || 4")
  assert_eq(score.lines[0].tokens.length(), 4) // 1, |, |, 4
  // %% は % 2つ（反復記号2つ）として解釈される（2小節リピートは将来拡張）
  let score2 = parse_ok("1 %%")
  assert_eq(score2.lines[0].tokens.length(), 3)
}

///|
/// | は空白なしでもトークンを区切る
test "barline splits without spaces" {
  let score = parse_ok("1|4")
  assert_eq(score.lines[0].tokens.length(), 3) // 1, |, 4
}

///|
/// フロントマター: コロン後の空白なし・小文字キーは不正
test "frontmatter field format details" {
  match parse_ok("---\nkey:G\n---\n1").meta {
    Some(meta) => @debug.assert_eq(meta.key, Some("G"))
    None => fail("Expected meta")
  }
  match single_error("---\nkey: g\n---\n1").kind {
    @chord_language.InvalidKey(_) => () // OK
    _ => fail("Expected InvalidKey for lowercase g")
  }
}

///|
/// 本文途中の --- はフロントマターではなく行エラーになる（正常行は残る）
test "dashes mid-body are line errors" {
  let r = @chord_language.parse("1 4\n---\n5")
  assert_eq(r.score.lines.length(), 2) // 1行目と3行目
  assert_eq(r.errors.length(), 1)
}

///|
/// JSON 出力に行番号が入る
test "json output includes line numbers" {
  let json = parse_ok("---\nkey: G\n---\n1 4").to_json()
  assert_true(json.contains("\"line\": 4"))
}

///|
/// % 反復記号: 独立トークンとしてパースされる
test "parse repeat marks" {
  let score = parse_ok("1 % % | %")
  assert_eq(score.lines[0].tokens.length(), 5)
  match score.lines[0].tokens[1] {
    @chord_language.Repeat => () // OK
    _ => fail("Expected Repeat token")
  }
  // 空白なしでも区切られる
  let score2 = parse_ok("1%4")
  assert_eq(score2.lines[0].tokens.length(), 3)
  // JSON 出力
  let json = parse_ok("1 %").to_json()
  assert_true(json.contains("\"type\": \"Repeat\""))
}

///|
/// - グループ: 1 スロット複数コード
test "parse dash chord groups" {
  match parse_ok("6m7 2-5").lines[0].tokens[1] {
    @chord_language.ChordGroup(nodes) => {
      assert_eq(nodes.length(), 2)
      match nodes[0].degree {
        @chord_language.D2 => () // OK
        _ => fail("Expected degree 2")
      }
    }
    _ => fail("Expected ChordGroup")
  }
  // 3 連結と色（個別のコードに付く）
  match parse_ok("1-2m7-5@red").lines[0].tokens[0] {
    @chord_language.ChordGroup(nodes) => {
      assert_eq(nodes.length(), 3)
      match nodes[2].color {
        Some(@chord_language.Red) => () // OK
        _ => fail("Expected red on third chord")
      }
      match nodes[0].color {
        None => () // OK
        _ => fail("Expected no color on first chord")
      }
    }
    _ => fail("Expected ChordGroup")
  }
  // JSON 出力
  let json = parse_ok("2-5").to_json()
  assert_true(json.contains("\"type\": \"ChordGroup\""))
  assert_true(json.contains("chords"))
  // 括弧内の文字は分割されない（テンションは - を含まないが深度追跡の確認）
  match parse_ok("1M7(b9,s11)-5").lines[0].tokens[0] {
    @chord_language.ChordGroup(nodes) => assert_eq(nodes.length(), 2)
    _ => fail("Expected ChordGroup")
  }
}

///|
/// - グループのエラー: 空パートと不正コード（位置はパート開始基準）
test "error on invalid dash groups" {
  for input in ["2-", "-5", "2--5"] {
    let r = @chord_language.parse(input)
    assert_true(r.errors.length() > 0)
  }
  // グループ内の不正コードは位置がずれて報告される: "1 2-8x" の 8x はカラム4
  let e = single_error("1 2-8x")
  @debug.assert_eq(e.position, Some(4))
}

///|
/// セクションラベル: [名前] の単独行
test "parse section labels" {
  let score = parse_ok("[Aメロ]\n| 1M7 % |\n\n[サビ #2]\n| 4M7 5 |")
  assert_eq(score.sections.length(), 2)
  assert_eq(score.sections[0].name, "Aメロ")
  assert_eq(score.sections[0].line_number, 1)
  assert_eq(score.sections[1].name, "サビ #2") // # もラベル名の一部
  assert_eq(score.sections[1].line_number, 4)
  // JSON 出力
  let json = score.to_json()
  assert_true(json.contains("sections"))
  assert_true(json.contains("Aメロ"))
  // [A] 1 4 のように後続トークンがある行はラベルではない（行エラー）
  let r = @chord_language.parse("[A] 1 4")
  assert_true(r.errors.length() > 0)
}

///|
/// 歌詞行: > で始まる行がコードに左から割り当たる
test "parse lyric lines" {
  let score = parse_ok(
    "| 1M7 % | 4M7 5 |\n> ひかりの _ さきへ ゆこう",
  )
  let line = score.lines[0]
  assert_eq(line.lyrics.length(), 4)
  @debug.assert_eq(line.lyrics[0], Some("ひかりの"))
  @debug.assert_eq(line.lyrics[1], None) // _ 単独 = 歌詞なし
  @debug.assert_eq(line.lyrics[2], Some("さきへ"))
  @debug.assert_eq(line.lyrics[3], Some("ゆこう"))
  // 断片中の _ はスペースになる
  let score2 = parse_ok("1 4\n> sweet_home yeah")
  @debug.assert_eq(score2.lines[0].lyrics[0], Some("sweet home"))
  // 断片が足りない分は歌詞なし
  let score3 = parse_ok("1 4 5\n> ひとつ")
  assert_eq(score3.lines[0].lyrics.length(), 3)
  @debug.assert_eq(score3.lines[0].lyrics[1], None)
  // 歌詞は自由テキスト（# もそのまま歌詞になる）
  let score4 = parse_ok("1\n> #1")
  @debug.assert_eq(score4.lines[0].lyrics[0], Some("#1"))
  // JSON 出力
  assert_true(parse_ok("1\n> ラ").to_json().contains("lyrics"))
}

///|
/// 歌詞行のエラー
test "lyric line errors" {
  // 断片超過: エラーになるがコード行の描画は維持される
  let r1 = @chord_language.parse("1 4\n> あ い う")
  assert_eq(r1.errors.length(), 1)
  match r1.errors[0].kind {
    @chord_language.TooManyLyricFragments(3, 2) => () // OK
    _ => fail("Expected TooManyLyricFragments(3,2)")
  }
  assert_eq(r1.score.lines.length(), 1)
  assert_eq(r1.score.lines[0].lyrics.length(), 2) // 先頭から割り当て
  // 孤立した歌詞行（直前がコード行でない）
  let r2 = @chord_language.parse("> あ")
  match r2.errors[0].kind {
    @chord_language.OrphanLyricLine => () // OK
    _ => fail("Expected OrphanLyricLine")
  }
  // ラベル行の直後もコード行ではないので孤立
  let r3 = @chord_language.parse("1 4\n[A]\n> あ")
  match r3.errors[0].kind {
    @chord_language.OrphanLyricLine => () // OK
    _ => fail("Expected OrphanLyricLine after section")
  }
  // 空行を挟んだ場合も孤立（直後の行のみ）
  let r4 = @chord_language.parse("1 4\n\n> あ")
  match r4.errors[0].kind {
    @chord_language.OrphanLyricLine => () // OK
    _ => fail("Expected OrphanLyricLine after blank")
  }
}

///|
/// N.C.: NC / N.C. の両表記
test "parse no chord" {
  let score = parse_ok("| NC 1 | N.C. 4 |")
  match score.lines[0].tokens[1] {
    @chord_language.NoChord => () // OK
    _ => fail("Expected NoChord for NC")
  }
  match score.lines[0].tokens[4] {
    @chord_language.NoChord => () // OK
    _ => fail("Expected NoChord for N.C.")
  }
  // JSON 出力
  assert_true(parse_ok("NC").to_json().contains("\"type\": \"NoChord\""))
  // NC に注釈は付けられない
  let r = @chord_language.parse("NC@red")
  assert_true(r.errors.length() > 0)
}

///|
/// 空拍 _: スロットを占有し、空白なしでも区切られる
test "parse empty beats" {
  let score = parse_ok("| 1 _ _ _ |")
  assert_eq(score.lines[0].tokens.length(), 6) // | 1 _ _ _ |
  match score.lines[0].tokens[2] {
    @chord_language.EmptyBeat => () // OK
    _ => fail("Expected EmptyBeat")
  }
  // 空白なし区切り
  let score2 = parse_ok("1_4")
  assert_eq(score2.lines[0].tokens.length(), 3)
  // JSON 出力
  assert_true(parse_ok("1 _").to_json().contains("\"type\": \"EmptyBeat\""))
}

///|
/// 歌詞は N.C. と空拍にも割り当たる（|| の空セルには割り当たらない）
test "lyrics map to nc and empty beats" {
  let score = parse_ok("| 1 _ NC % |\n> ひ か り の")
  assert_eq(score.lines[0].lyrics.length(), 4)
  @debug.assert_eq(score.lines[0].lyrics[1], Some("か")) // 空拍に歌詞
  @debug.assert_eq(score.lines[0].lyrics[2], Some("り")) // N.C. に歌詞
  // 空拍4つで1コードを4拍に伸ばして歌詞を敷く使い方
  let score2 = parse_ok("1 _ _ _\n> ひ か り の")
  assert_eq(score2.lines[0].lyrics.length(), 4)
}

///|
/// フロントマター bpm
test "parse frontmatter bpm" {
  match parse_ok("---\nkey: G\nbpm: 132\n---\n1").meta {
    Some(meta) => @debug.assert_eq(meta.bpm, Some(132))
    None => fail("Expected meta")
  }
  // 不正な bpm
  for
    input in [
      "---\nbpm: abc\n---\n1", "---\nbpm: 10\n---\n1", "---\nbpm: 999\n---\n1",
    ] {
    match single_error(input).kind {
      @chord_language.InvalidTempo(_) => () // OK
      _ => fail("Expected InvalidTempo for " + input)
    }
  }
  // JSON 出力
  assert_true(
    parse_ok("---\nbpm: 132\n---\n1").to_json().contains("\"bpm\": 132"),
  )
}

///|
/// フロントマター time: ホワイトリスト制
test "parse frontmatter time signature" {
  match parse_ok("---\ntime: 6/8\n---\n1").meta {
    Some(meta) => @debug.assert_eq(meta.time, Some("6/8"))
    None => fail("Expected meta")
  }
  assert_true(
    parse_ok("---\ntime: 3/4\n---\n1").to_json().contains("\"time\": \"3/4\""),
  )
  // ホワイトリスト外はエラー
  for
    input in [
      "---\ntime: 4/5\n---\n1", "---\ntime: 13/8\n---\n1", "---\ntime: 44\n---\n1",
    ] {
    match single_error(input).kind {
      @chord_language.InvalidTimeSignature(_) => () // OK
      _ => fail("Expected InvalidTimeSignature for " + input)
    }
  }
}
