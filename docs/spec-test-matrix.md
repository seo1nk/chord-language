# 仕様とテストの対応表(spec-test-matrix)

> **このファイルは仕様とテストの対応を管理する。仕様改訂時・テスト追加時に更新すること(Phase 3 完了条件)。**
>
> - 生成日: 2026-07-03
> - 対象仕様: `docs/chord.md` v1.2.2
> - 対象テスト: `src/parser_test.mbt`(パーサ)/ `src/renderer_test.mbt`(HTML レンダラ)— 計 37 テスト全パス時点
> - 表記: テストは `ファイル名: "テスト名"` で示す。1 つのテストが複数項目をカバーしてよい。対応が無い項目は「⚠ 未カバー」、テストが間接的にしか検証していない項目は「△ 間接」と付記する(いずれも末尾の「未カバー・弱カバー一覧」に集約)。

---

## 1. パースの基本方針(§パースの基本方針)

| 仕様の記述 | 対応テスト |
|---|---|
| fail-fast しない(エラー行を除外し部分 AST + エラー列を返す) | parser_test.mbt: "collect errors and keep valid lines" / parser_test.mbt: "parse_to_json structured errors" / renderer_test.mbt: "render error fallback to html" |
| エラーに行番号(1-indexed)と position(行内 0-indexed)が付く | parser_test.mbt: "error positions are line-relative" / parser_test.mbt: "parse_to_json structured errors" / parser_test.mbt: "collect errors and keep valid lines"(行番号の存在) |
| 空入力・空白のみの入力は空の楽譜として正常 | parser_test.mbt: "parse empty input" |

## 2. トークンの定義(§トークンの定義)

| 仕様の記述 | 対応テスト |
|---|---|
| コード = 空白区切りのトークン(構造は §構文例 の各行で対応付け) | 下記 §3 参照 |
| 改行 = 楽譜上の改行、空行は無視(行番号カウントには含む) | parser_test.mbt: "parse multiple lines" / parser_test.mbt: "line numbers account for blank lines" |
| 小節線 `\|` | parser_test.mbt: "parse with barlines" / renderer_test.mbt: "render basic score to html" |
| 予約トークン: `\|\|` は現行 2 つの小節線として解釈 | ⚠ 未カバー(実挙動は BarLine×2 を確認済み) |
| 予約トークン: `%` 等は認識できない文字列としてエラー | ⚠ 未カバー(実挙動は InvalidDegree を確認済み。仕様の「認識できない文字列」分類とはズレあり) |
| コメント: `#` から行末まで無視、行頭なら行全体 | parser_test.mbt: "parse comments" |
| 空白文字の扱い(スペース・タブ・連続空白を区切りとして扱う) | parser_test.mbt: "parse with multiple spaces and tabs" |

## 3. 構文例(§構文例)

### 3.1 基本形

| 構文例 | 対応テスト |
|---|---|
| `1` | parser_test.mbt: "parse basic chords" / renderer_test.mbt: "render basic score to html"(`I` 表示) |
| `3m` | △ 間接 — parser_test.mbt: "parse basic chords"(`3m7` として通過)。セブンスなし単独の `3m`、および quality=Minor の AST 値を直接検証するテストは無い |
| `b7` | △ 間接 — parser_test.mbt: "parse multiple lines"(`b7 1` を通過)/ "parse chords with bass notes"(`b7/5` を通過)。ルートの Flat アクシデンタルの AST 値検証は無い |
| `s4` | parser_test.mbt: "parse complex chords"(`s4M7(...)` の Sharp を AST 検証) |

### 3.2 セブンス付き

| 構文例 | 対応テスト |
|---|---|
| `5M7` | parser_test.mbt: "parse basic chords"(`4M7`)/ "parse complex chords"(MajorSeventh を AST 検証) |
| `2m7` | parser_test.mbt: "parse basic chords"(`3m7`) |
| `47` | parser_test.mbt: "parse spec success examples"(`17` の Seventh を AST 検証) |
| `36` | parser_test.mbt: "parse spec success examples"(`16 36` の Sixth を AST 検証) |
| `4add6` / `4add9` | △ 間接 — parser_test.mbt: "parse spec success examples"(`1add2 1add4 1add6 1add9 3add11 5add13` を通過、トークン数のみ検証。add の degree の AST 値検証は無い) |
| `3dim7` | parser_test.mbt: "parse spec success examples"(`3dim7 2aug` の Diminish を AST 検証) |

### 3.3 オルタレーション(括弧なし・括弧あり)

| 構文例 | 対応テスト |
|---|---|
| `1sus4`(括弧なし) | △ 間接 — parser_test.mbt: "parse spec success examples"(`1sus4 4M7b5` をパース成功のみ確認、AST 検証なし) |
| `4M7b5`(括弧なし) | parser_test.mbt: "parse spec success examples"(`1M7b5(b9)` で FlatFive alteration を AST 検証) |
| `1(sus4)`(括弧あり) | parser_test.mbt: "parse complex chords"(`1M7(sus4,9)`) |
| `4M7(b5)`(括弧あり) | parser_test.mbt: "parse complex chords"(`2m7(b5)`)/ renderer_test.mbt: "render multiline score to html"(`(♭5)` 表示) |

### 3.4 テンション付き

| 構文例 | 対応テスト |
|---|---|
| `1M7(b9)` | parser_test.mbt: "parse options with spaces inside parentheses"(`1M7(b9, s11)`) |
| `5(b9)` | parser_test.mbt: "parse complex chords" |
| `2m7(b9,s11)` | parser_test.mbt: "parse complex chords"(`s4M7(b5,b9,s11)`) |
| `4M7(9,s11)` | parser_test.mbt: "parse complex chords"(9 は `1M7(sus4,9)`、s11 は `s4M7(b5,b9,s11)` で個別にカバー) |
| `1M7(b9,s11,b13)` | ⚠ 未カバー — テンション `b13`(および `13` / `s9` / `11`)をパースするテストが存在しない |

### 3.5 オルタレーションとテンションの混在

| 構文例 | 対応テスト |
|---|---|
| `1M7(b5,b9)` | parser_test.mbt: "parse complex chords"(`s4M7(b5,b9,s11)`) |
| `2m7(sus4,9)` | parser_test.mbt: "parse complex chords"(`1M7(sus4,9)`) |
| `4(b5,s11)` | parser_test.mbt: "parse complex chords" |
| `1M7(sus4,b9,13)` | ⚠ 未カバー — `13` を含むためカバーするテストが無い(sus4/b9 部分のみ "parse complex chords" が該当) |
| `1M7b5(b9)`(括弧外+括弧内、両方保持) | parser_test.mbt: "parse spec success examples"(直接。alteration と options の両立を AST 検証) |
| `2m7sus4(9,s11)`(括弧外 sus+括弧内) | △ 間接 — 直接のテストは無い(b5 混在 `1M7b5(b9)` のみ検証。実挙動はパース成功を確認済み) |

### 3.6 ベース音付き

| 構文例 | 対応テスト |
|---|---|
| `5/3` | parser_test.mbt: "parse chords with bass notes" |
| `b7/5` | parser_test.mbt: "parse chords with bass notes" |
| `1M7(b9)/3` | parser_test.mbt: "parse chords with bass notes" |
| `4M7(b5,b9)/b3` | parser_test.mbt: "parse chords with bass notes"(`1/b3` の Flat を AST 検証)/ "parse color on complex chord"(`s4M7(b5,b9)/b3@red`)/ renderer_test.mbt: "render multiline score to html"(`/♭III` 表示) |
| `1/s4`(ベースのシャープ) | △ 間接 — ベースのアクシデンタルは Flat(`1/b3`)のみ検証。Sharp ベースのテストは無い |

### 3.7 色アノテーション付き

| 構文例 | 対応テスト |
|---|---|
| `1@red` | parser_test.mbt: "parse chord colors" |
| `3m7@blue` | parser_test.mbt: "parse chord colors" |
| `s4M7(b5,b9)/b3@green` | parser_test.mbt: "parse color on complex chord"(同形を @red で検証。green 自体は "parse chord colors" で検証) |

### 3.8 複雑な例

| 構文例 | 対応テスト |
|---|---|
| `s4M7b5(b9,s11)/b3`(括弧外 b5+括弧内+ベース) | △ 間接 — 完全な同時形のテストは無い。"parse spec success examples"(`1M7b5(b9)` 混在)+ "parse color on complex chord"(`s4M7(b5,b9)/b3@red`)の組み合わせで各要素はカバー |
| `s4M7(b5,b9,s11)/b3` | parser_test.mbt: "parse complex chords"(ベースなし同形)+ "parse chords with bass notes" / renderer_test.mbt: "render multiline score to html"(`s4M7(b5,b9)/b3`) |
| `1(sus4,b9,s11,b13)` | ⚠ 未カバー — `b13` を含むテストが無い |

### 3.9 完全な入力例(§完全な入力例)

| 構文例 | 対応テスト |
|---|---|
| `1 3m7 4M7 5 \| b7 1` ほか 3 行(仕様書の完全な入力例そのまま) | parser_test.mbt: "parse spec example"(直接) |

## 4. エラーハンドリング一覧(§エラーハンドリング)

### 4.1 行単位のエラー収集

| 仕様の記述 | 対応テスト |
|---|---|
| エラー行は部分 AST から除外、`kind`/`message`/`line`/`position`/`token` を記録 | parser_test.mbt: "collect errors and keep valid lines" / "parse_to_json structured errors" |
| 1 行に複数の不正トークンがあれば複数エラー | parser_test.mbt: "collect errors and keep valid lines"(4 行目 `1M7() b9x` から 2 エラー) |

### 4.2 構文エラー

| 項目 | 対応テスト |
|---|---|
| 不正なディグリー(1-7 以外) | parser_test.mbt: "error on invalid degree" / "error positions are line-relative" / renderer_test.mbt: "render error fallback to html" |
| 不正なセブンス表記 | ⚠ 未カバー — InvalidSeventh の kind を検証するテストが無い(実挙動: `1add5` → InvalidSeventh を確認済み) |
| 不正なテンション表記 | parser_test.mbt: "error on invalid tension"(`1(b8)`) |
| 不正なオプション表記 | △ 間接 — 実装上 InvalidTension に統合されており "error on invalid tension" が間接カバー(`1(foo)` のような非テンション文字列の直接テストは無い。実挙動: InvalidTension を確認済み) |
| 括弧の不一致 | parser_test.mbt: "error on unmatched parenthesis"(`1M7(b9`) |
| 空の括弧 `()` | parser_test.mbt: "error on empty parentheses"(`1M7()`) |
| カンマの不正使用(`(,b9)` / `(b9,)` / `(b9,,s11)`) | parser_test.mbt: "error on invalid comma usage"(仕様の 3 例すべて直接) |
| 不正な色指定(`1@yellow` / `1@` / `1@red/3`) | parser_test.mbt: "error on color issues"(仕様の 3 例すべて直接) |
| 認識できない文字列 | ⚠ 未カバー — UnrecognizedToken の kind を検証するテストが無い("collect errors and keep valid lines" の `8x`/`b9x` は InvalidDegree に分類されるため該当しない。実挙動: `1x` / `1m7x` → UnrecognizedToken を確認済み) |

### 4.3 意味エラー

| 項目 | 対応テスト |
|---|---|
| セブンスの重複(`1M7M7`, `17M7` など) | parser_test.mbt: "error on duplicate seventh"(`1M77` / `17M7`)/ "error positions are line-relative"(position 検証)。仕様例の `1M7M7` / ガイドラインの `1M7add9` は未検証(実挙動: DuplicateSeventh を確認済み) |
| スラッシュベースでディグリー欠落(`1/`, `1/b`) | parser_test.mbt: "error on bass degree issues"(`1M7/` → MissingBassDegree)。`1/b` は未検証(実挙動: MissingBassDegree を確認済み) |
| `1/8` は InvalidDegree | parser_test.mbt: "error on bass degree issues"(直接) |
| `/3`(ルートディグリー欠落)は InvalidDegree | ⚠ 未カバー(実挙動: InvalidDegree を確認済み) |
| 不正な sus ディグリー(2/4/6 以外、括弧内 `sus11` / `sus` も) | parser_test.mbt: "error on invalid sus degree"(`1sus5` / `1(sus11)` / `1(sus)` / `1(sus5)` — 括弧外・括弧内とも直接) |

### 4.4 フロントマターのエラー(v1.2)

| 項目 | 対応テスト |
|---|---|
| 閉じ `---` の欠落(UnclosedFrontmatter) | parser_test.mbt: "frontmatter errors" |
| 未知のフィールド(InvalidFrontmatterField) | parser_test.mbt: "frontmatter errors"(`tempo: 120`、エラー行番号も検証) |
| 不正なキー名(InvalidKey) | parser_test.mbt: "frontmatter errors"(`key: H` / `key: Gm`) |

### 4.5 エラーメッセージ例

| 項目 | 対応テスト |
|---|---|
| `Invalid degree '8' ...` の文言 | renderer_test.mbt: "render error fallback to html"(行番号・position 込みの文言を検証) |
| 他 5 例(EmptyParentheses / DuplicateSeventh / MissingBassDegree / InvalidCommaUsage / InvalidColor)の message 文言 | ⚠ 未カバー — kind のみ検証しており、文言のスナップショットは無い |

## 5. パーサーの振る舞い仕様まとめ(§パーサーの振る舞い仕様まとめ、全 23 行)

| 表の行(ケース / 入力例) | 対応テスト |
|---|---|
| 基本形 `1` | parser_test.mbt: "parse basic chords" / renderer_test.mbt: "render basic score to html" |
| セブンス優先 `1M7` | parser_test.mbt: "parse spec success examples"(`17` → Seventh / `16` → Sixth)/ "parse complex chords"(MajorSeventh) |
| add系 `1add9` | △ 間接 — parser_test.mbt: "parse spec success examples"(パース成功のみ。`{type:'add', degree:'9'}` の AST 検証なし) |
| 括弧外オルタレーション `1M7b5` | parser_test.mbt: "parse spec success examples" |
| 括弧内オプション `1M7(b5)` | parser_test.mbt: "parse complex chords" |
| 混在記法 `1M7b5(b9)` | parser_test.mbt: "parse spec success examples"(直接、両方保持を AST 検証) |
| スラッシュベース `1/3` | parser_test.mbt: "parse chords with bass notes" |
| スラッシュベース+アクシデンタル `1/b3` | parser_test.mbt: "parse chords with bass notes"(直接、Flat を AST 検証) |
| 色アノテーション `1@red` | parser_test.mbt: "parse chord colors"(直接) |
| 色+複雑なコード `4M7(b5)/b3@green` | parser_test.mbt: "parse color on complex chord"(`s4M7(b5,b9)/b3@red` で bass+options+color の共存を検証) |
| 複数スペース `1  3m  5` | parser_test.mbt: "parse with multiple spaces and tabs" |
| タブ区切り `1	3m	5` | parser_test.mbt: "parse with multiple spaces and tabs" |
| 括弧内空白 `1M7(b9, s11)` | parser_test.mbt: "parse options with spaces inside parentheses"(直接、`2m7( b5 )` も) |
| コメント `1 4 # メモ` | parser_test.mbt: "parse comments" |
| 空入力 `` | parser_test.mbt: "parse empty input" |
| 複数行エラー `1 4\n8x\n5 1` | parser_test.mbt: "collect errors and keep valid lines" / renderer_test.mbt: "render error fallback to html" |
| 空の括弧 `1M7()` | parser_test.mbt: "error on empty parentheses" |
| セブンス重複 `1M77` | parser_test.mbt: "error on duplicate seventh" |
| スラッシュのみ `1/` | parser_test.mbt: "error on bass degree issues"(`1M7/` で同一経路を検証) |
| カンマ不正使用 `1(,b9)` | parser_test.mbt: "error on invalid comma usage"(直接) |
| 不正な色 `1@yellow` | parser_test.mbt: "error on color issues"(直接) |
| 色名欠落 `1@` | parser_test.mbt: "error on color issues"(直接) |
| 色が末尾以外 `1@red/3` | parser_test.mbt: "error on color issues"(直接) |

## 6. フロントマター仕様(§Chord ブロックとフロントマター)

| 仕様の記述 | 対応テスト |
|---|---|
| ブロック先頭の `---` 〜 `---` で `key` を宣言できる | parser_test.mbt: "parse frontmatter with key" |
| アクシデンタル付きキー(`F#` / `Bb`) | parser_test.mbt: "parse frontmatter with key" |
| 本文の行番号はフロントマター込みで元ソース基準 | parser_test.mbt: "parse frontmatter with key"(`line_number == 4`) |
| フロントマター省略時は meta なし(既定値 C は表示層が適用) | parser_test.mbt: "no frontmatter means no meta" |
| `key` フィールド無しのフロントマターは meta あり・key なし | parser_test.mbt: "no frontmatter means no meta" |
| 閉じ `---` 必須(欠落は UnclosedFrontmatter) | parser_test.mbt: "frontmatter errors" |
| v1.2 のフィールドは `key` のみ(他は InvalidFrontmatterField) | parser_test.mbt: "frontmatter errors" |
| キー名書式 `A`〜`G` + 任意の `#`/`b`(違反は InvalidKey、マイナーキー `Gm` も不可) | parser_test.mbt: "frontmatter errors" |
| フロントマターにエラーがあっても本文はパースされる | parser_test.mbt: "frontmatter errors"(`key: H` でも本文 1 行が AST に残る) |
| JSON 出力に `meta.key` が出る(`{"type":"ScoreBlock","meta":{"key":"G"},...}`) | parser_test.mbt: "json output" |
| 既定値 `C` の適用(表示層)・タブ切り替え・キープルダウン(移調) | ⚠ 未カバー(Phase 4 予定の表示仕様。実装自体が未着手) |
| フロントマターは「先頭にのみ」置ける(途中の `---` の扱い) | ⚠ 未カバー(実挙動: 途中の `---` は行エラーになることを確認済み) |
| Markdown への埋め込み(`:::` フェンス / ` ```chord ` 互換 / ` ```chord:code `) | ⚠ 未カバー(本リポジトリのテスト対象外。markdown.mbt フォーク側の実装) |

## 7. 色アノテーション仕様(§トークンの定義 1. / §表示仕様)

| 仕様の記述 | 対応テスト |
|---|---|
| `@` + `blue` / `red` / `green` の 3 色 | parser_test.mbt: "parse chord colors"(3 色すべて + 色なしを AST 検証) |
| コードトークンの末尾にのみ置ける(スラッシュベースより後) | parser_test.mbt: "parse color on complex chord"(`.../b3@red`)/ "error on color issues"(`1@red/3` がエラー) |
| blue/red/green 以外・色名欠落はエラー | parser_test.mbt: "error on color issues"(`1@yellow` / `1@`) |
| 色名は小文字のみ(大文字はエラー) | ⚠ 未カバー(実挙動: `1@RED` → InvalidColor を確認済み) |
| 表示用アノテーション(CSS クラス `chord--red` 等として出力) | renderer_test.mbt: "render colored chords to html" / "chord css is scoped"(`.chord--red` の存在) |
| 色は両タブ・全キーで保持される | ⚠ 未カバー(Phase 4 のタブ表示が未実装。現行のディグリー表示での保持のみ "render colored chords to html" が検証) |

## 8. ディグリー表示の変換規則(§ディグリー表示の変換規則 — レンダラ)

| 仕様の記述 | 対応テスト |
|---|---|
| `1`〜`7` → `I`〜`VII`(ローマ数字) | renderer_test.mbt: "render basic score to html"(I/III/IV/V)/ "render multiline score to html"(II)。**VI / VII は未検証** |
| `b` → `♭`、`s` → `#` | renderer_test.mbt: "render multiline score to html"(`#IV` / `(♭5,♭9)` / `/♭III`) |
| ベース音のディグリーもローマ数字 | renderer_test.mbt: "render multiline score to html"(`/♭III`) |
| 括弧内テンション `(b9,s11) → (♭9,#11)` | △ 間接 — `♭9` は検証済みだが `s11 → #11` / `13` / `b13` の表示変換テストは無い |

## 9. JSON 出力・堅牢性(§JSON出力例 ほか)

| 仕様の記述 | 対応テスト |
|---|---|
| `parse_to_json` のエンベロープ(`success` / `data` / `errors`) | parser_test.mbt: "parse_to_json structured errors" |
| 構造化エラー(`kind` / `line` / `position`) | parser_test.mbt: "parse_to_json structured errors" |
| ScoreAST の JSON 形状(`ScoreBlock` / `meta` / `lines`) | parser_test.mbt: "json output" |
| (仕様外の堅牢性)制御文字のエスケープ / HTML エスケープ / CSS スコープ | parser_test.mbt: "error json escapes control characters" / renderer_test.mbt: "render error escapes html in source" / "chord css is scoped" |

---

## 未カバー・弱カバー一覧(gaps)

**⚠ 完全に未カバー**

1. テンション `s9` / `11` / `b13` / `13` のパース(構文例 `1M7(b9,s11,b13)` / `1M7(sus4,b9,13)` / `1(sus4,b9,s11,b13)` が未カバー)
2. 不正なセブンス表記(InvalidSeventh。例 `1add5`)のエラーテスト
3. 認識できない文字列(UnrecognizedToken。例 `1x` / `1m7x`)のエラーテスト
4. ルートディグリー欠落 `/3` → InvalidDegree の分類テスト
5. 予約トークンの現行動作(`||` → 小節線 2 つ、`%` → エラー)
6. 色名の大文字 `1@RED` がエラーになること(小文字のみ規定)
7. エラーメッセージ文言(InvalidDegree 以外の 5 例)
8. フロントマターが先頭以外にある場合の挙動
9. Phase 4 の表示仕様(既定値 C の適用・タブ切り替え・キープルダウン・色の両タブ保持)— 実装未着手のため当面は対象外として管理
10. Markdown 埋め込み(`:::` / ` ```chord ` / ` ```chord:code `)— markdown.mbt フォーク側

**△ 間接カバー(検証強化を推奨)**

11. add 系の AST 値(`1add9` → `{type:'add', degree:'9'}`)— パース成功とトークン数のみ確認
12. 括弧なしオルタレーション単独(`1sus4` / `4M7b5`)の AST 値 — パース成功のみ確認
13. quality Minor(`3m`)/ Augment(`2aug`)の AST 値 — Diminish のみ検証
14. ルートの Flat アクシデンタル(`b7`)の AST 値と表示(`♭VII`)— Sharp のみ検証
15. ベースのシャープ `1/s4` — Flat ベース(`1/b3`)のみ検証
16. 括弧外 sus + 括弧内オプションの混在 `2m7sus4(9,s11)` — b5 混在のみ検証
17. `1/b`(アクシデンタルのみのベース)→ MissingBassDegree — `1M7/` のみ検証
18. セブンス重複の仕様例 `1M7M7` / `1M7add9` — `1M77` / `17M7` のみ検証
19. 「不正なオプション表記」— 実装上 InvalidTension に統合され `1(b8)` のみ検証(`1(foo)` 等の非テンション文字列は未検証)
20. ローマ数字表示の `VI` / `VII`、テンション表示の `s11 → #11` — レンダラのゴールデンテストに含まれていない


---

## 更新記録

### 2026-07-03 更新（対応表生成後のギャップ解消）

生成時の 37 テストに対し、検証で確認された未カバー項目のうち以下を**テスト追加で解消**した（55 テスト時点）:

| 解消したギャップ | 追加テスト |
|---|---|
| テンション s9/11/b13/13 | parser_test.mbt: "parse all tensions" |
| 正常系 sus2 / sus6 | parser_test.mbt: "parse sus2 and sus6" |
| add の AST 値・ルート Flat・単独 3m・aug・ベース Sharp・sus 混在 | parser_test.mbt: "parse ast values for add, accidentals, qualities" |
| InvalidSeventh | parser_test.mbt: "error on invalid seventh" |
| UnrecognizedToken（1x / 1m7x / 1b9)） | parser_test.mbt: "error on unrecognized token" |
| /3 → InvalidDegree | parser_test.mbt: "error on missing root degree" |
| 1M7M7 / 1M7add9 → DuplicateSeventh | parser_test.mbt: "error on duplicate seventh spec examples" |
| 1/b → MissingBassDegree | parser_test.mbt: "error on bass with accidental only" |
| 1@RED → InvalidColor | parser_test.mbt: "error on uppercase color name" |
| エラーの token フィールド | parser_test.mbt: "error records token field" |
| 予約トークンの現行動作（\|\| は小節線2つ、% はエラー） | parser_test.mbt: "reserved tokens current behavior" |
| 空白なし \| 区切り | parser_test.mbt: "barline splits without spaces" |
| フロントマターの key:G（空白なし）/ 小文字キー | parser_test.mbt: "frontmatter field format details" |
| 本文途中の --- | parser_test.mbt: "dashes mid-body are line errors" |
| JSON の lines[].line 値 | parser_test.mbt: "json output includes line numbers" |
| VI/VII/♭VII とテンション記号表示 | renderer_test.mbt: "render roman numerals and tension symbols" |
| 1 行複数エラーの埋め込み表示 | renderer_test.mbt: "render multiple errors in one line" |
| フロントマターつき描画 | renderer_test.mbt: "render with frontmatter" |

あわせて仕様側も修正した:
- 「不正なオプション表記」を「不正なテンション表記」に統合（実装の InvalidTension 分類に合わせ、InvalidOption はエラー種別から削除）
- 予約トークンのエラー分類の記述を実挙動（InvalidDegree 等の構文エラー）に合わせて修正

**意図的に未カバーのまま残す項目**:
- Phase 4 表示仕様（既定値 C の適用・タブ切り替え・キープルダウン移調）— 未実装のためテスト不能
- Markdown 埋め込み（::: / ```chord / ```chord:code）— markdown.mbt フォーク側の e2e（e2e/chord.spec.ts、10 件）でカバー
- エラーメッセージ文言の全種スナップショット — kind 検証で十分とし、文言は renderer golden の代表例のみ


### 2026-07-03 更新（Phase 4: 実音変換・ウィジェット）

| 仕様項目 | 対応テスト |
|---|---|
| 実音変換の基本テーブル（key C / G） | transpose_test.mbt: "transpose basic table" |
| 異名同音スペリング（F# の 7=E#、Bb の b3=D♭、E の b6=C） | transpose_test.mbt: "transpose enharmonic spelling" |
| 複雑なコードの変換（クオリティ・テンション・ベース・色の引き継ぎ） | transpose_test.mbt: "transpose complex chord" |
| ウィジェット HTML（タブ・キー select・両パネル・data 属性） | transpose_test.mbt: "render widget html" |
| key 未宣言の既定値 C | transpose_test.mbt: "widget defaults to key C" |
| パースエラー時のウィジェットフォールバック | transpose_test.mbt: "widget falls back on parse errors" |
| 不正キーのフォールバック | transpose_test.mbt: "notes html falls back on invalid key" |
| SSR（md_to_html）でのウィジェット生成・互換・エラー | markdown.mbt フォーク src/chord_fence_test.mbt: "colon fence renders chord widget via md_to_html" ほか 2 件 |
| タブ切替・プルダウン移調・既定 C（ブラウザ動作） | markdown.mbt フォーク e2e/chord.spec.ts: "tab switch shows note names in declared key" / "key pulldown transposes to any key" / "key defaults to C when frontmatter is absent" |

### 2026-07-03 更新（v1.3.0: % 反復・~ グループ・レイアウト）

| 仕様項目 | 対応テスト |
|---|---|
| % 反復記号（独立トークン・空白なし区切り・JSON） | parser_test.mbt: "parse repeat marks" |
| ~ グループ（2/3 連結・個別色・JSON） | parser_test.mbt: "parse tilde chord groups" |
| ~ グループのエラー（空パート・位置） | parser_test.mbt: "error on invalid tilde groups" |
| %% の現行動作（反復記号 2 つ） | parser_test.mbt: "reserved tokens current behavior" |
| % / ~ グループの描画（ゴールデン） | renderer_test.mbt: "render repeat and group slots" |
| % / ~ グループのブラウザ描画と移調（key Eb で 2~5 → F/B♭） | markdown.mbt フォーク e2e/chord.spec.ts: "repeat marks and tilde groups render and transpose" |

### 2026-07-03 更新（v1.4.0: セクションラベル・歌詞行）

| 仕様項目 | 対応テスト |
|---|---|
| セクションラベル（単独行・コメント可・行番号・JSON・非ラベル行の扱い） | parser_test.mbt: "parse section labels" |
| 歌詞行の割り当て（`_` スキップ・`_`=スペース・不足分・#は歌詞・JSON） | parser_test.mbt: "parse lyric lines" |
| 歌詞行のエラー（断片超過・孤立: 先頭/ラベル後/空行後） | parser_test.mbt: "lyric line errors" |
| セクション・歌詞・グループ分配・% への歌詞の描画（ゴールデン） | renderer_test.mbt: "render sections and lyrics" |
| ブラウザ描画と移調タブでの保持 | markdown.mbt フォーク e2e/chord.spec.ts: "section labels and lyric lines render under chords" |

### 2026-07-03 更新（v1.5.0: N.C.・空拍）

| 仕様項目 | 対応テスト |
|---|---|
| NC / N.C. の両表記・JSON・注釈不可 | parser_test.mbt: "parse no chord" |
| 空拍 `_`（スロット占有・空白なし区切り・JSON） | parser_test.mbt: "parse empty beats" |
| 歌詞の N.C./空拍への割り当て（\|\| 空セルは対象外） | parser_test.mbt: "lyrics map to nc and empty beats" |
| N.C.・空拍・歌詞の描画（ゴールデン） | renderer_test.mbt: "render nc and empty beats with lyrics" |
| ブラウザ描画（歌詞スペース `_` 含む） | markdown.mbt フォーク e2e/chord.spec.ts: "no-chord and empty beats render with lyrics" |

### 2026-07-03 更新（v1.5.2: 画像コピー）

| 仕様項目 | 対応テスト |
|---|---|
| ウィジェットに画像コピーボタンが含まれる | transpose_test.mbt: "render widget html" |
| クリックで PNG がクリップボードに入る・フィードバック表示・ラベル復帰 | markdown.mbt フォーク e2e/chord.spec.ts: "copy score as image button copies a PNG to clipboard" |

### 2026-07-03 更新（v1.6.0: 再生機能）

| 仕様項目 | 対応テスト |
|---|---|
| 基本発音（key C の 1 = [36,60,64,67]・tempo 既定 100・totalBeats） | playback_test.mbt: "playback basic chord" |
| `_` 持続（dur 伸長）と `%` 再打鍵 | playback_test.mbt: "playback sustain and repeat" |
| N.C. 無音・N.C. をまたぐ持続なし | playback_test.mbt: "playback nc silence" |
| グループ等分割（0.5 拍） | playback_test.mbt: "playback group subdivision" |
| キー変換・テンション・sus・スラッシュベースの音 | playback_test.mbt: "playback voicing details" |
| tempo 反映・カーソルのセル番号 | playback_test.mbt: "playback tempo and cursor" |
| フロントマター tempo（検証・エラー・JSON） | parser_test.mbt: "parse frontmatter tempo" |
| ブラウザ再生（▶/■ トグル・カーソルハイライト・自動停止） | markdown.mbt フォーク e2e/chord.spec.ts: "play button starts playback..." |

### 2026-07-03 更新（v1.7.0: bpm・拍子・ベース刻み）

| 仕様項目 | 対応テスト |
|---|---|
| ベーストラック分離（上声/ベース・4/4 で 4 打・既定 BPM 120） | playback_test.mbt: "playback basic chord" |
| 拍子によるスロット長と刻み（3/4・6/8 付点4分・2/2） | playback_test.mbt: "playback time signatures" |
| bpm 正式名と tempo エイリアス | playback_test.mbt: "playback bpm field and alias" / parser_test.mbt: "parse frontmatter tempo" |
| time のホワイトリスト検証（4/5・13/8・44 はエラー） | parser_test.mbt: "parse frontmatter time signature" |


---

### 2026-07-04: 仕様 v1.0 正式化

実装済み仕様を正式 v1.0 として確定し、docs/chord.md を再構成した。あわせて旧記法の互換実装を削除:
- `~` グループ区切り（→ `-` のみ）
- `tempo:` エイリアス（→ `bpm:` のみ。ScoreMeta のフィールドも bpm に改名）
- ` ```chord ` フェンス互換（→ `:::` のみ。フォーク内部の言語キーは chord-block に改名）
- 再生 JSON のフィールド tempo → bpm、パッケージ版数 1.0.0

上記に伴い、削除された互換のテスト（~ エイリアス・tempo エイリアス・```chord ウィジェット化）も削除・置換済み。

---

### 2026-07-12 更新（v1.1: 転調指示 `[key: 値]`）

仕様 v1.1 で転調指示を追加（設計ノート: docs/modulation-design.md）。あわせて api.md §4 に `[小文字識別子: 値]` のディレクティブ予約領域を明文化した。

| 仕様項目 | 対応テスト |
|---|---|
| 単独行の転調（相対 `[key: +1]` / 絶対 `[key: F]`・セクションにならない・KeyChangeTok の AST 値・JSON 形状） | parser_test.mbt: "parse key changes" |
| 空白バリエーション（`[ key : -2 ]` `[key:Eb]`） | parser_test.mbt: "parse key changes" |
| 相対値の境界（`+11` / `-11` / `-1` は有効、`+0` / `+12` は不正） | parser_test.mbt: "parse key changes" / "key change errors" |
| インライン転調がスロット・歌詞割り当てを消費しない | parser_test.mbt: "parse key changes" / playback_test.mbt: "playback key changes"（cursor 数の不変） |
| 行頭の転調指示が先頭小節線の leading 判定・セル数に影響しない（`[key: +2] \|\| 1` = `\|\| 1`） | playback_test.mbt: "playback key changes" |
| `[Key: F]`（大文字）・`[keys: 1]` はセクションラベルのまま | parser_test.mbt: "parse key changes" |
| InvalidKeyChange（`+0` / `+12` / `H` / 値なし / 小文字キー / `+2x`・エラー行の除外・セクションバッジ化しない） | parser_test.mbt: "key change errors" |
| 未クローズ `[key:+2` → InvalidKeyChange | parser_test.mbt: "key change errors" |
| インラインのエラー位置（行内 0-indexed）・行番号 | parser_test.mbt: "key change errors" |
| グループ内不可（`1-[key:+2]5` → InvalidDegree）・トークン先頭以外の `[`（`1[key:+2]`）は従来どおりエラー | parser_test.mbt: "key change errors" |
| `key:` で始まらないブラケットの従来挙動保存（`[サビ] 1 4` → InvalidDegree） | parser_test.mbt: "key change errors" |
| 転調単独行の直後の歌詞行（TooManyLyricFragments の専用メッセージ） | parser_test.mbt: "key change errors" |
| 実音表示: 単独行 +1（ラスサビ）で以降が新キー基準・`Key D♭ (+1)` バッジ | transpose_test.mbt: "transpose key change standalone" |
| 実音表示: インライン +2 の合成（C → D → E）・キー名のみのチップ | transpose_test.mbt: "transpose key change inline" |
| プルダウン移調 δ の絶対キーへの一様適用（宣言 C・選択 D で `[key: F]` → G） | transpose_test.mbt: "transpose key change delta on absolute" / playback_test.mbt: "playback key changes" |
| δ=0 の絶対キーは原文綴りを尊重（`[key: C#]` → C#） | transpose_test.mbt: "transpose key change spelling preserved" |
| 相対転調の正準 12 キー表スペリング（E +1 → F、F# +2 → Ab） | transpose_test.mbt: "transpose key change canonical spelling" |
| ウィジェット両パネルのチップ（実音 = `Key A♭ (+1)`、ディグリー = 宣言キー基準で解決した `key A♭ (+1)` — 2026-07-20 改訂） | transpose_test.mbt: "widget key change chips" |
| 転調バッジの描画（.chord-modline / .chord-mod・前置チップ・行末の後置チップ・スコア末尾の宙吊り指示・列数不変） | renderer_test.mbt: "render key change badges" |
| エラー文書でも正しい転調行は描画され続ける | renderer_test.mbt: "render key change with error lines" |
| 再生: 転調後の tonic 反映・`%` の実音固定・totalBeats 不変・絶対キーへの δ 適用 | playback_test.mbt: "playback key changes" |
| エラー行除外でキー領域が「指示なし」として継続する帰結 | playback_test.mbt: "playback key changes" |
| ブラウザ表示・移調・再生（プレイグラウンド目視） | markdown.mbt フォーク側で JS 再ビルド後に確認（本リポジトリ単体では対象外） |

---

### 2026-07-13 更新（v1.2: グループ内の空きパート `_`・転調チップの小節上部表示）

| 仕様項目 | 対応テスト |
|---|---|
| `5-_-5-6`（4 パートの 2 拍目が空き・AST は GroupHold） | parser_test.mbt: "parse group holds" |
| 先頭・末尾の空きパート（`_-5` / `5-_`） | parser_test.mbt: "parse group holds" |
| 単独 `_` は従来どおり空拍（`1_4` = 3 スロット） | parser_test.mbt: "parse group holds" |
| JSON: 空きパートは `{"type": "Hold"}`（`chords` 配列内） | parser_test.mbt: "parse group holds" |
| 空パート（`5-_-`）は従来どおりエラー | parser_test.mbt: "parse group holds" |
| 再生: 空きパートは直前の発音を等分割ぶん持続（先頭の空きは前スロットから・無ければ無音） | playback_test.mbt: "playback group holds" |
| 描画: 空きパートは空セルで間隔だけを占有（ゴールデン） | renderer_test.mbt: "render group holds" |
| インライン転調チップの小節上部表示（コンパクト形 +1 / F） | renderer_test.mbt: "render key change badges" / transpose_test.mbt（ゴールデン更新） |
| 歌詞の拍分割（`_-あいあい` = 後半から・`うえ-_` = 前半のみ。%・_ スロットでも可） | renderer_test.mbt: "render lyric beat split" |
| グループ歌詞のパート数一致分配・不一致フォールバックは従来どおり（分割しない） | parser_test.mbt: "parse group holds" / renderer_test.mbt: "render sections and lyrics"（既存ゴールデン不変） |
| 転調直後の小節の転調前ディグリー薄表示(=V。次の小節線で解除・単独行は次行の最初の小節・% 等は非対象) | renderer_test.mbt: "render previous-key degrees after modulation" / "render key change badges" |
| 再生中の転調チップ点灯(.chord-mod--playing) | markdown.mbt フォーク側ランタイム(chord-widget.ts)+ 実機目視 |

---

### 2026-07-20 更新（ディグリータブの転調チップも解決後キー併記に）

| 仕様項目 | 対応テスト |
|---|---|
| ディグリータブの転調チップ: 単独行 `key D♭ (+1)`(絶対は `key F`)・インラインはキー名のみ(宣言キー基準・綴りは実音タブと同じ) | renderer_test.mbt: "render key change badges" ほかゴールデン / transpose_test.mbt: "widget key change chips" |

---

### 2026-07-21 更新（ダブルアクシデンタルの異名同音化）

| 仕様項目 | 対応テスト |
|---|---|
| DSL のアクシデンタル合成でダブル以上になる実音は正準表で綴り直す(D♭ の `b6` = `B♭♭` → `A`。ルート・スラッシュベース両方。シングルは理論綴りのまま) | transpose_test.mbt: "respell double accidentals" |
| 綴り優先度の伝播: 異名同音側の綴り(C#・Gb)を選ぶと転調先も同じ向きの正準表で綴る(C# +2 → D#)。既定綴り(Db・F#)は従来どおり | transpose_test.mbt: "spelling preference propagates to modulations" |
| ウィジェットの ♯/♭ トグル(黒鍵 5 スロットの綴り一括切り替え。実体はフォーク側 chord-widget.ts) | transpose_test.mbt: "widget has spelling toggle" / markdown.mbt 側 E2E | 
