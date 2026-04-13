/// LexTokenをTokenに変換
fn lex_token_to_token(lex_token: LexToken, line_number: Int) -> Result[Token, ParseError] {
  match lex_token {
    ChordToken(chord_str) => {
      match parse_chord(chord_str) {
        Ok(chord_node) => Ok(Chord(chord_node))
        Err(e) => {
          // エラーに行番号を付与
          Err(ParseError {
            kind: e.kind,
            position: e.position,
            line: Some(line_number),
            token: e.token
          })
        }
      }
    }
    BarLineToken => Ok(BarLine)
    LineBreak => {
      // LineBreakはここでは処理しない（行分割時に除去済み）
      // 万が一来た場合はエラー
      Err(ParseError::syntax(
        UnrecognizedToken("LineBreak in token stream"),
        line=Some(line_number)
      ))
    }
  }
}

/// 1行分のLexTokenをLineに変換
fn parse_line(lex_tokens: Array[LexToken], line_number: Int) -> Result[Line, ParseError] {
  let tokens: Array[Token] = []
  
  for lex_token in lex_tokens {
    match lex_token_to_token(lex_token, line_number) {
      Ok(token) => tokens.push(token)
      Err(e) => return Err(e)
    }
  }
  
  Ok(Line { tokens })
}

///| 入力文字列をパースしてScoreASTを返す
/// 
/// # 例
/// ```moonbit
/// let input = "1 3m7 4M7 5 | b7 1"
/// match parse(input) {
///   Ok(ast) => println(ast.to_json())
///   Err(e) => println(e.to_string())
/// }
/// ```
pub fn parse(input: String) -> Result[ScoreAST, ParseError] {
  // 1. 字句解析
  let lex_result = tokenize(input)
  
  // 2. 行ごとにグループ化
  let line_groups = group_by_lines(lex_result)
  
  // 3. 各行をパース
  let lines: Array[Line] = []
  
  for i, line_group in line_groups.iter() {
    let line_number = i + 1  // 1-indexed
    match parse_line(line_group, line_number) {
      Ok(line) => lines.push(line)
      Err(e) => return Err(e)
    }
  }
  
  Ok(ScoreAST { lines })
}

/// ScoreASTを文字列に変換（デバッグ用）
pub fn ScoreAST::to_string(self: ScoreAST) -> String {
  let line_strs = self.lines.map(fn(line) { line_to_string(line) })
  "ScoreAST {\n" + line_strs.map(fn(s) { "  " + s }).join("\n") + "\n}"
}

/// Lineを文字列に変換（デバッグ用）
fn line_to_string(line: Line) -> String {
  let token_strs = line.tokens.map(token_to_string)
  "Line [" + token_strs.join(", ") + "]"
}

/// Tokenを文字列に変換（デバッグ用）
fn token_to_string(token: Token) -> String {
  match token {
    Chord(node) => "Chord(" + chord_node_to_string(node) + ")"
    BarLine => "BarLine"
  }
}

/// ChordNodeを文字列に変換（デバッグ用）
fn chord_node_to_string(node: ChordNode) -> String {
  let acc = match node.accidental {
    Some(Sharp) => "s"
    Some(Flat) => "b"
    None => ""
  }
  let deg = node.degree.to_string()
  let qual = match node.quality {
    Some(Minor) => "m"
    Some(Diminish) => "dim"
    Some(Augment) => "aug"
    None => ""
  }
  let sev = match node.seventh {
    Some(Seventh) => "7"
    Some(MajorSeventh) => "M7"
    Some(Sixth) => "6"
    Some(Add(d)) => "add" + d.to_string()
    None => ""
  }
  let alt = match node.alteration {
    Some(FlatFive) => "b5"
    Some(Sus(d)) => "sus" + d.to_string()
    None => ""
  }
  let opts = if node.options.length() > 0 {
    "(" + node.options.map(option_to_string).join(",") + ")"
  } else {
    ""
  }
  let bass_str = match node.bass {
    Some(b) => {
      let b_acc = match b.accidental {
        Some(Sharp) => "s"
        Some(Flat) => "b"
        None => ""
      }
      "/" + b_acc + b.degree.to_string()
    }
    None => ""
  }
  
  acc + deg + qual + sev + alt + opts + bass_str
}

/// ChordOptionを文字列に変換（デバッグ用）
fn option_to_string(opt: ChordOption) -> String {
  match opt {
    TensionOpt(FlatNine) => "b9"
    TensionOpt(Nine) => "9"
    TensionOpt(SharpNine) => "s9"
    TensionOpt(Eleven) => "11"
    TensionOpt(SharpEleven) => "s11"
    TensionOpt(FlatThirteen) => "b13"
    TensionOpt(Thirteen) => "13"
    AlterationOpt(FlatFive) => "b5"
    AlterationOpt(Sus(d)) => "sus" + d.to_string()
  }
}

/// テスト用関数
pub fn test_parse() -> Unit {
  // テスト1: 基本的なコード列
  let input1 = "1 3m7 4M7 5"
  println("Test 1: \{input1}")
  match parse(input1) {
    Ok(ast) => println("Success:\n\{ast.to_string()}\n")
    Err(e) => println("Error: \{e.to_string()}\n")
  }
  
  // テスト2: バーライン付き
  let input2 = "1 3m7 | 4M7 5"
  println("Test 2: \{input2}")
  match parse(input2) {
    Ok(ast) => println("Success:\n\{ast.to_string()}\n")
    Err(e) => println("Error: \{e.to_string()}\n")
  }
  
  // テスト3: 複数行
  let input3 = "1 3m7 4M7 5 | b7 1\ns4M7(b5,b9,s11) 5 |\n2m7(b5) 5(b9) 1M7(sus4,9)"
  println("Test 3: Multiple lines")
  match parse(input3) {
    Ok(ast) => println("Success:\n\{ast.to_string()}\n")
    Err(e) => println("Error: \{e.to_string()}\n")
  }
  
  // テスト4: ベース音付き
  let input4 = "5/3 b7/5 1M7(b9)/3"
  println("Test 4: \{input4}")
  match parse(input4) {
    Ok(ast) => println("Success:\n\{ast.to_string()}\n")
    Err(e) => println("Error: \{e.to_string()}\n")
  }
  
  // テスト5: エラーケース（不正なディグリー）
  let input5 = "1 8m7 4M7"
  println("Test 5 (Error case): \{input5}")
  match parse(input5) {
    Ok(ast) => println("Success:\n\{ast.to_string()}\n")
    Err(e) => println("Error: \{e.to_string()}\n")
  }
  
  // テスト6: エラーケース（空の括弧）
  let input6 = "1M7() 3m7"
  println("Test 6 (Error case): \{input6}")
  match parse(input6) {
    Ok(ast) => println("Success:\n\{ast.to_string()}\n")
    Err(e) => println("Error: \{e.to_string()}\n")
  }
  
  // テスト7: エラーケース（ベースディグリー欠落）
  let input7 = "1M7/ 3m7"
  println("Test 7 (Error case): \{input7}")
  match parse(input7) {
    Ok(ast) => println("Success:\n\{ast.to_string()}\n")
    Err(e) => println("Error: \{e.to_string()}\n")
  }
  
  // テスト8: 複雑な例
  let input8 = "1 3m7 4M7 5 | b7 1\ns4M7(b5,b9,s11) 5 |\n2m7(b5) 5(b9) 1M7(sus4,9)"
  println("Test 8: Complex (from spec)")
  match parse(input8) {
    Ok(ast) => {
      println("Success:\n\{ast.to_string()}\n")
      println("Line count: \{ast.lines.length()}")
      for i, line in ast.lines.iter() {
        println("Line \{i + 1}: \{line.tokens.length()} tokens")
      }
    }
    Err(e) => println("Error: \{e.to_string()}\n")
  }
}

///| ScoreASTをJSON文字列に変換
/// 
/// # 例
/// ```moonbit
/// let ast = parse("1 3m7 4M7 5").unwrap()
/// let json = ast.to_json()
/// println(json)
/// ```
pub fn ScoreAST::to_json(self: ScoreAST) -> String {
  let lines_json = self.lines.map(line_to_json)
  "{\n  \"type\": \"ScoreBlock\",\n  \"lines\": [\n" + 
  lines_json.map(fn(s) { "    " + s }).join(",\n") + 
  "\n  ]\n}"
}

fn line_to_json(line: Line) -> String {
  let tokens_json = line.tokens.map(token_to_json)
  "{\n      \"tokens\": [\n" + 
  tokens_json.map(fn(s) { "        " + s }).join(",\n") + 
  "\n      ]\n    }"
}

fn token_to_json(token: Token) -> String {
  match token {
    Chord(node) => "{\n          \"type\": \"Chord\",\n          \"chord\": " + chord_node_to_json(node) + "\n        }"
    BarLine => "{ \"type\": \"BarLine\" }"
  }
}

fn chord_node_to_json(node: ChordNode) -> String {
  let parts: Array[String] = []
  
  // accidental
  match node.accidental {
    Some(Sharp) => parts.push("\"accidental\": \"s\"")
    Some(Flat) => parts.push("\"accidental\": \"b\"")
    None => {}
  }
  
  // degree
  parts.push("\"degree\": \"" + node.degree.to_string() + "\"")
  
  // quality
  match node.quality {
    Some(Minor) => parts.push("\"quality\": \"m\"")
    Some(Diminish) => parts.push("\"quality\": \"dim\"")
    Some(Augment) => parts.push("\"quality\": \"aug\"")
    None => {}
  }
  
  // seventh
  match node.seventh {
    Some(Seventh) => parts.push("\"seventh\": { \"type\": \"seventh\", \"value\": \"7\" }")
    Some(MajorSeventh) => parts.push("\"seventh\": { \"type\": \"seventh\", \"value\": \"M7\" }")
    Some(Sixth) => parts.push("\"seventh\": { \"type\": \"seventh\", \"value\": \"6\" }")
    Some(Add(d)) => parts.push("\"seventh\": { \"type\": \"add\", \"degree\": \"" + d.to_string() + "\" }")
    None => {}
  }
  
  // alteration
  match node.alteration {
    Some(FlatFive) => parts.push("\"alteration\": { \"type\": \"b5\" }")
    Some(Sus(d)) => parts.push("\"alteration\": { \"type\": \"sus\", \"degree\": \"" + d.to_string() + "\" }")
    None => {}
  }
  
  // options
  if node.options.length() > 0 {
    let opts_json = node.options.map(option_to_json)
    parts.push("\"options\": [" + opts_json.join(", ") + "]")
  }
  
  // bass
  match node.bass {
    Some(b) => parts.push("\"bass\": " + bass_note_to_json(b))
    None => {}
  }
  
  "{ " + parts.join(", ") + " }"
}

fn option_to_json(opt: ChordOption) -> String {
  match opt {
    TensionOpt(FlatNine) => "{ \"type\": \"b9\" }"
    TensionOpt(Nine) => "{ \"type\": \"9\" }"
    TensionOpt(SharpNine) => "{ \"type\": \"s9\" }"
    TensionOpt(Eleven) => "{ \"type\": \"11\" }"
    TensionOpt(SharpEleven) => "{ \"type\": \"s11\" }"
    TensionOpt(FlatThirteen) => "{ \"type\": \"b13\" }"
    TensionOpt(Thirteen) => "{ \"type\": \"13\" }"
    AlterationOpt(FlatFive) => "{ \"type\": \"b5\" }"
    AlterationOpt(Sus(d)) => "{ \"type\": \"sus\", \"degree\": \"" + d.to_string() + "\" }"
  }
}

fn bass_note_to_json(bass: BassNote) -> String {
  let parts: Array[String] = []
  
  match bass.accidental {
    Some(Sharp) => parts.push("\"accidental\": \"s\"")
    Some(Flat) => parts.push("\"accidental\": \"b\"")
    None => {}
  }
  
  parts.push("\"degree\": \"" + bass.degree.to_string() + "\"")
  
  "{ " + parts.join(", ") + " }"
}
