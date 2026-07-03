///|
/// UTF-16コードユニットを \uXXXX 形式にエスケープする
fn escape_unicode(code : Int) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder::new()
  sb.write_string("\\u")
  let mut shift = 12
  while shift >= 0 {
    match digits.get_char((code >> shift) & 0xF) {
      Some(c) => sb.write_char(c)
      None => ()
    }
    shift = shift - 4
  }
  sb.to_string()
}

///|
/// JSON 文字列リテラル用のエスケープ。
/// 引用符・バックスラッシュに加え、制御文字（U+0000-U+001F）と
/// サロゲート（U+D800-U+DFFF、ペアも各コードユニットを \uXXXX 化。JSONとして等価）を処理する。
fn escape_json_string(s : String) -> String {
  let sb = StringBuilder::new()
  for i in 0..<s.length() {
    let code = s.at(i).to_int()
    if code == 0x22 {
      sb.write_string("\\\"")
    } else if code == 0x5C {
      sb.write_string("\\\\")
    } else if code < 0x20 || (code >= 0xD800 && code <= 0xDFFF) {
      sb.write_string(escape_unicode(code))
    } else {
      match code.to_char() {
        Some(c) => sb.write_char(c)
        None => sb.write_string(escape_unicode(code))
      }
    }
  }
  sb.to_string()
}

///|
/// JavaScriptから呼び出せるパース関数
///
/// 入力: コード譜の文字列
/// 出力: 成功時はJSON文字列、失敗時はエラーJSON
pub fn parse_to_json(input : String) -> String {
  match parse(input) {
    Ok(ast) =>
      // 成功時のJSONレスポンス
      "{\"success\":true,\"data\":" + ast.to_json() + "}"
    Err(e) => {
      // エラー時のJSONレスポンス
      // NOTE: エラー内容の構造化（kind/line/position）は Phase 3 (derive(ToJson) 化) で行う。
      let error_message = escape_json_string(e.to_string())
      "{\"success\":false,\"error\":\"" + error_message + "\"}"
    }
  }
}

///|
/// バージョン情報を返す（デバッグ用）
pub fn get_version() -> String {
  "0.1.0"
}

///|
/// パーサーのヘルスチェック（デバッグ用）
pub fn health_check() -> String {
  "OK"
}
