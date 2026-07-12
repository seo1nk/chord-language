///|
/// JavaScript から呼び出せるパース関数（JS ターゲットの公開 API）
///
/// 入力: コード譜の文字列
/// 出力: JSON 文字列
///   { "success": Bool,            // エラーが 1 件も無いか
///     "data": { ...ScoreAST... }, // 部分 AST（エラー行は除外）
///     "errors": [ { kind, message, line, position, token }, ... ] }
pub fn parse_to_json(input : String) -> String {
  let result = parse(input)
  let obj : Map[String, Json] = {}
  obj["success"] = if result.errors.is_empty() { true } else { false }
  obj["data"] = result.score.to_json_value()
  obj["errors"] = Json::array(result.errors.map(fn(e) { e.to_json_value() }))
  Json::object(obj).stringify()
}

///|
/// バージョン情報を返す（デバッグ用）
pub fn get_version() -> String {
  "1.1.0"
}

///|
/// パーサーのヘルスチェック（デバッグ用）
pub fn health_check() -> String {
  "OK"
}
