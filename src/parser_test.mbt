///|
/// 基本的なコードのパーステスト
test "parse basic chords" {
  let input = "1 3m7 4M7 5"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 4)
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// バーライン付きのパーステスト
test "parse with barlines" {
  let input = "1 3m7 | 4M7 5"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 5) // 4 chords + 1 barline

      // 3番目のトークンがBarLineであることを確認
      match ast.lines[0].tokens[2] {
        @chord_language.BarLine => () // OK
        _ => fail("Expected BarLine at position 2")
      }
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// 複数行のパーステスト
test "parse multiple lines" {
  let input = "1 3m7 4M7 5\nb7 1"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 2)
      assert_eq(ast.lines[0].tokens.length(), 4)
      assert_eq(ast.lines[1].tokens.length(), 2)
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// 複雑なコードのパーステスト
test "parse complex chords" {
  let input = "s4M7(b5,b9,s11) 2m7(b5) 5(b9) 1M7(sus4,9)"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 4)

      // 最初のコードをチェック
      match ast.lines[0].tokens[0] {
        @chord_language.Chord(node) => {
          // アクシデンタルがSharpであることを確認
          match node.accidental {
            Some(@chord_language.Sharp) => () // OK
            _ => fail("Expected Sharp accidental")
          }
          // ディグリーが4であることを確認
          match node.degree {
            @chord_language.D4 => () // OK
            _ => fail("Expected degree 4")
          }
          // セブンスがM7であることを確認
          match node.seventh {
            Some(@chord_language.MajorSeventh) => () // OK
            _ => fail("Expected MajorSeventh")
          }
          // オプションが3つあることを確認
          assert_eq(node.options.length(), 3)
        }
        _ => fail("Expected Chord token")
      }
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// ベース音付きコードのパーステスト
test "parse chords with bass notes" {
  let input = "5/3 b7/5 1M7(b9)/3"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 3)

      // 各コードがベース音を持つことを確認
      for token in ast.lines[0].tokens {
        match token {
          @chord_language.Chord(node) =>
            match node.bass {
              Some(_) => () // OK
              None => fail("Expected bass note")
            }
          _ => fail("Expected Chord token")
        }
      }
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// エラーケース: 不正なディグリー
test "error on invalid degree" {
  let input = "1 8m7 4M7"
  match @chord_language.parse(input) {
    Ok(_) => fail("Should have failed with invalid degree")
    Err(e) =>
      // エラーが InvalidDegree であることを確認
      match e.kind {
        @chord_language.InvalidDegree(_) => () // OK
        _ => fail("Expected InvalidDegree error")
      }
  }
}

///|
/// エラーケース: 空の括弧
test "error on empty parentheses" {
  let input = "1M7() 3m7"
  match @chord_language.parse(input) {
    Ok(_) => fail("Should have failed with empty parentheses")
    Err(e) =>
      match e.kind {
        @chord_language.EmptyParentheses => () // OK
        _ => fail("Expected EmptyParentheses error")
      }
  }
}

///|
/// エラーケース: ベースディグリー欠落
test "error on missing bass degree" {
  let input = "1M7/ 3m7"
  match @chord_language.parse(input) {
    Ok(_) => fail("Should have failed with missing bass degree")
    Err(e) =>
      match e.kind {
        @chord_language.MissingBassDegree => () // OK
        _ => fail("Expected MissingBassDegree error")
      }
  }
}

///|
/// エラーケース: 不正なsusディグリー
test "error on invalid sus degree" {
  let input = "1sus5 3m7"
  match @chord_language.parse(input) {
    Ok(_) => fail("Should have failed with invalid sus degree")
    Err(e) =>
      match e.kind {
        @chord_language.InvalidSusDegree(_) => () // OK
        _ => fail("Expected InvalidSusDegree error")
      }
  }
}

///|
/// JSON出力のテスト
test "json output" {
  let input = "1 3m7"
  match @chord_language.parse(input) {
    Ok(ast) => {
      let json = ast.to_json()
      // JSON文字列に必要な要素が含まれていることを確認
      assert_true(json.contains("ScoreBlock"))
      assert_true(json.contains("lines"))
      assert_true(json.contains("tokens"))
      assert_true(json.contains("Chord"))
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// 仕様書の例のパーステスト
test "parse spec example" {
  let input = "1 3m7 4M7 5 | b7 1\ns4M7(b5,b9,s11) 5 |\n2m7(b5) 5(b9) 1M7(sus4,9)"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 3)

      // Line 1: 7 tokens (4 chords + 1 barline + 2 chords)
      assert_eq(ast.lines[0].tokens.length(), 7)

      // Line 2: 3 tokens (2 chords + 1 barline)
      assert_eq(ast.lines[1].tokens.length(), 3)

      // Line 3: 3 tokens (3 chords)
      assert_eq(ast.lines[2].tokens.length(), 3)
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// 複数スペース・タブのテスト
test "parse with multiple spaces and tabs" {
  let input = "1  3m7\t\t4M7   5"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 4)
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// add系セブンスのテスト
test "parse add sevenths" {
  let input = "1add9 3add11 5add13"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 3)

      // 各コードのセブンスがAdd型であることを確認
      for token in ast.lines[0].tokens {
        match token {
          @chord_language.Chord(node) =>
            match node.seventh {
              Some(@chord_language.Add(_)) => () // OK
              _ => fail("Expected Add seventh")
            }
          _ => fail("Expected Chord token")
        }
      }
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// 色アノテーション: 基本
test "parse chord colors" {
  let input = "1@red 3m7@blue 4M7@green 5"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 4)
      match ast.lines[0].tokens[0] {
        @chord_language.Chord(node) =>
          match node.color {
            Some(@chord_language.Red) => () // OK
            _ => fail("Expected Red color on first chord")
          }
        _ => fail("Expected Chord token")
      }
      match ast.lines[0].tokens[1] {
        @chord_language.Chord(node) =>
          match node.color {
            Some(@chord_language.Blue) => () // OK
            _ => fail("Expected Blue color on second chord")
          }
        _ => fail("Expected Chord token")
      }
      match ast.lines[0].tokens[2] {
        @chord_language.Chord(node) =>
          match node.color {
            Some(@chord_language.Green) => () // OK
            _ => fail("Expected Green color on third chord")
          }
        _ => fail("Expected Chord token")
      }
      // 色指定なしのコードは None
      match ast.lines[0].tokens[3] {
        @chord_language.Chord(node) =>
          match node.color {
            None => () // OK
            _ => fail("Expected no color on fourth chord")
          }
        _ => fail("Expected Chord token")
      }
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// 色アノテーション: 複雑なコードとの組み合わせ（末尾位置）
test "parse color on complex chord" {
  let input = "s4M7(b5,b9)/b3@red"
  match @chord_language.parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines[0].tokens.length(), 1)
      match ast.lines[0].tokens[0] {
        @chord_language.Chord(node) => {
          match node.color {
            Some(@chord_language.Red) => () // OK
            _ => fail("Expected Red color")
          }
          // 色以外の構成要素も保持されていることを確認
          match node.bass {
            Some(_) => () // OK
            None => fail("Expected bass note")
          }
          assert_eq(node.options.length(), 2)
        }
        _ => fail("Expected Chord token")
      }
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// 色アノテーション: JSON出力
test "color in json output" {
  let input = "1@red 5"
  match @chord_language.parse(input) {
    Ok(ast) => {
      let json = ast.to_json()
      assert_true(json.contains("\"color\": \"red\""))
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// エラーケース: 不正な色
test "error on invalid color" {
  let input = "1@yellow 3m7"
  match @chord_language.parse(input) {
    Ok(_) => fail("Should have failed with invalid color")
    Err(e) =>
      match e.kind {
        @chord_language.InvalidColor(_) => () // OK
        _ => fail("Expected InvalidColor error")
      }
  }
}

///|
/// エラーケース: 色名の欠落（@のみ）
test "error on missing color name" {
  let input = "1@ 3m7"
  match @chord_language.parse(input) {
    Ok(_) => fail("Should have failed with missing color name")
    Err(e) =>
      match e.kind {
        @chord_language.InvalidColor(_) => () // OK
        _ => fail("Expected InvalidColor error")
      }
  }
}

///|
/// エラーケース: 色が末尾以外に出現（@color の後にベース）
test "error on color not at end" {
  let input = "1@red/3"
  match @chord_language.parse(input) {
    Ok(_) => fail("Should have failed: color must be the last component")
    Err(e) =>
      match e.kind {
        @chord_language.InvalidColor(_) => () // OK
        _ => fail("Expected InvalidColor error")
      }
  }
}

///|
/// 空行を含む入力で行番号が元ソース基準になることを確認（レビュー指摘の回帰テスト）
test "line numbers account for blank lines" {
  let input = "1\n\n\n8"
  match @chord_language.parse(input) {
    Ok(_) => fail("Should have failed with invalid degree")
    Err(e) =>
      match e.line {
        Some(4) => () // 8 はソース4行目
        _ => fail("Expected error at line 4, got " + e.to_string())
      }
  }
}

///|
/// 括弧内の sus は度数を検証し InvalidSusDegree になる（レビュー指摘の回帰テスト）
test "error on invalid sus degree inside parentheses" {
  for input in ["1(sus11)", "1(sus)", "1(sus5)"] {
    match @chord_language.parse(input) {
      Ok(_) => fail("Should have failed: " + input)
      Err(e) =>
        match e.kind {
          @chord_language.InvalidSusDegree(_) => () // OK
          _ =>
            fail(
              "Expected InvalidSusDegree for " +
              input +
              ", got " +
              e.to_string(),
            )
        }
    }
  }
}

///|
/// 不正なベース度数は InvalidDegree を伝播する（レビュー指摘の回帰テスト）
test "error on invalid bass degree propagates" {
  match @chord_language.parse("1/8") {
    Ok(_) => fail("Should have failed with invalid degree")
    Err(e) =>
      match e.kind {
        @chord_language.InvalidDegree(_) => () // OK
        _ => fail("Expected InvalidDegree, got " + e.to_string())
      }
  }
  // ディグリー文字が無い場合は従来どおり MissingBassDegree
  match @chord_language.parse("1/") {
    Ok(_) => fail("Should have failed with missing bass degree")
    Err(e) =>
      match e.kind {
        @chord_language.MissingBassDegree => () // OK
        _ => fail("Expected MissingBassDegree, got " + e.to_string())
      }
  }
}

///|
/// 制御文字を含む入力でもエラーJSONが妥当であることを確認（レビュー指摘の回帰テスト）
test "error json escapes control characters" {
  let json = @chord_language.parse_to_json("1\u{01}")
  assert_true(json.contains("\\u0001"))
  // 生の制御文字が JSON に混入していないこと
  assert_true(not(json.contains("\u{01}")))
}
