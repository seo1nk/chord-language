///|
/// 基本的なコードのパーステスト
test "parse basic chords" {
  let input = "1 3m7 4M7 5"
  match parse(input) {
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
  match parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 5) // 4 chords + 1 barline

      // 3番目のトークンがBarLineであることを確認
      match ast.lines[0].tokens[2] {
        BarLine => {} // OK
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
  match parse(input) {
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
  match parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 4)

      // 最初のコードをチェック
      match ast.lines[0].tokens[0] {
        Chord(node) => {
          // アクシデンタルがSharpであることを確認
          match node.accidental {
            Some(Sharp) => {} // OK
            _ => fail("Expected Sharp accidental")
          }
          // ディグリーが4であることを確認
          match node.degree {
            D4 => {} // OK
            _ => fail("Expected degree 4")
          }
          // セブンスがM7であることを確認
          match node.seventh {
            Some(MajorSeventh) => {} // OK
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
  match parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 3)

      // 各コードがベース音を持つことを確認
      for token in ast.lines[0].tokens {
        match token {
          Chord(node) =>
            match node.bass {
              Some(_) => {} // OK
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
  match parse(input) {
    Ok(_) => fail("Should have failed with invalid degree")
    Err(e) =>
      // エラーが InvalidDegree であることを確認
      match e.kind {
        InvalidDegree(_) => {} // OK
        _ => fail("Expected InvalidDegree error")
      }
  }
}

///|
/// エラーケース: 空の括弧
test "error on empty parentheses" {
  let input = "1M7() 3m7"
  match parse(input) {
    Ok(_) => fail("Should have failed with empty parentheses")
    Err(e) =>
      match e.kind {
        EmptyParentheses => {} // OK
        _ => fail("Expected EmptyParentheses error")
      }
  }
}

///|
/// エラーケース: ベースディグリー欠落
test "error on missing bass degree" {
  let input = "1M7/ 3m7"
  match parse(input) {
    Ok(_) => fail("Should have failed with missing bass degree")
    Err(e) =>
      match e.kind {
        MissingBassDegree => {} // OK
        _ => fail("Expected MissingBassDegree error")
      }
  }
}

///|
/// エラーケース: 不正なsusディグリー
test "error on invalid sus degree" {
  let input = "1sus5 3m7"
  match parse(input) {
    Ok(_) => fail("Should have failed with invalid sus degree")
    Err(e) =>
      match e.kind {
        InvalidSusDegree(_) => {} // OK
        _ => fail("Expected InvalidSusDegree error")
      }
  }
}

///|
/// JSON出力のテスト
test "json output" {
  let input = "1 3m7"
  match parse(input) {
    Ok(ast) => {
      let json = ast.to_json()
      // JSON文字列に必要な要素が含まれていることを確認
      assert(json.contains("ScoreBlock"))
      assert(json.contains("lines"))
      assert(json.contains("tokens"))
      assert(json.contains("Chord"))
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}

///|
/// 仕様書の例のパーステスト
test "parse spec example" {
  let input = "1 3m7 4M7 5 | b7 1\ns4M7(b5,b9,s11) 5 |\n2m7(b5) 5(b9) 1M7(sus4,9)"
  match parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 3)

      // Line 1: 6 tokens (4 chords + 1 barline + 2 chords)
      assert_eq(ast.lines[0].tokens.length(), 7)

      // Line 2: 3 tokens (1 chord + 1 chord + 1 barline)
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
  match parse(input) {
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
  match parse(input) {
    Ok(ast) => {
      assert_eq(ast.lines.length(), 1)
      assert_eq(ast.lines[0].tokens.length(), 3)

      // 各コードのセブンスがAdd型であることを確認
      for token in ast.lines[0].tokens {
        match token {
          Chord(node) =>
            match node.seventh {
              Some(Add(_)) => {} // OK
              _ => fail("Expected Add seventh")
            }
          _ => fail("Expected Chord token")
        }
      }
    }
    Err(e) => fail("Parse failed: " + e.to_string())
  }
}
