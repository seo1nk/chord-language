///| JavaScriptから呼び出せるパース関数
/// 
/// 入力: コード譜の文字列
/// 出力: 成功時はJSON文字列、失敗時はエラーJSON
pub fn parse_to_json(input: String) -> String {
  match parse(input) {
    Ok(ast) => {
      // 成功時のJSONレスポンス
      "{\"success\":true,\"data\":" + ast.to_json() + "}"
    }
    Err(e) => {
      // エラー時のJSONレスポンス
      let error_message = e.to_string().replace("\"", "\\\"")
      "{\"success\":false,\"error\":\"" + error_message + "\"}"
    }
  }
}

///| バージョン情報を返す（デバッグ用）
pub fn get_version() -> String {
  "1.0.0"
}

///| パーサーのヘルスチェック（デバッグ用）
pub fn health_check() -> String {
  "OK"
}
