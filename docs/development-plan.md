# 開発プラン(詳細)

[roadmap.md](./roadmap.md) の背景となる現状評価・技術分析・アーキテクチャ判断・戦略選定の経緯をまとめる。調査日: 2026-07-03。調査対象は本リポジトリ(HEAD a4e349c)と `/Users/seoink/Documents/markdown.mbt`(mizchi/markdown v0.6.4)、およびコード譜 DSL の先行事例(Web 調査)。

## 目次

1. [現状評価: chord-language 実装](#1-現状評価-chord-language-実装)
2. [ビルド失敗の原因と修復方針](#2-ビルド失敗の原因と修復方針)
3. [markdown.mbt 統合ポイント分析](#3-markdownmbt-統合ポイント分析)
4. [アーキテクチャ決定の分析](#4-アーキテクチャ決定の分析)
5. [仕様 v1.0 と実装の乖離](#5-仕様-v10-と実装の乖離)
6. [仕様自体の穴(将来拡張)](#6-仕様自体の穴将来拡張)
7. [テストカバレッジの穴](#7-テストカバレッジの穴)
8. [先行事例調査](#8-先行事例調査)
9. [リポジトリ運用方針](#9-リポジトリ運用方針)
10. [戦略選定の経緯](#10-戦略選定の経緯)

---

## 1. 現状評価: chord-language 実装

### 最重要の発見

**HEAD コミット a4e349c の実装は、一度もコンパイルに成功していない。** import 問題を修正しても 35 件のコンパイルエラーが残り、`test/parser_test.mbt` の 13 テストは一度も実行されていない。パーサロジックの正しさは机上検証のみである。「HEAD に完全実装がある」という認識は改める必要がある — あるのは「仕様に忠実に設計された、未検証の実装」である。

### ファイル別の状態

| ファイル | 作業ツリー | 評価 |
|---------|-----------|------|
| `src/ast.mbt` | **未コミット削除**(D) | 型定義は仕様に忠実で健全。**復元して土台にする** |
| `src/parse_error.mbt` | 存在(HEAD と同一) | エラー体系は健全。土台にする |
| `src/lexer.mbt` | **未コミット削除**(D) | `@buffer` 依存+mut 漏れバグ。参照実装として復元し、書き直す |
| `src/chord_parser.mbt` | **未コミット削除**(D) | 439 行。API ドリフトの主戦場。参照実装として復元し、StringView ベースで書き直す |
| `src/parser.mbt` | 存在(HEAD と同一) | `chord_node_to_string` / `option_to_string` が chord_parser.mbt と二重定義 |
| `src/wasm_api.mbt` | **未コミット削除**(D) | `parse_to_json` のエスケープ不備あり。JSON 出力刷新時に書き直す |
| `test/parser_test.mbt` | 存在 | クロスパッケージ import なのに `@src` 修飾なしでコンパイル不能 |

削除 4 ファイルは `git checkout HEAD -- src/` で完全復元できる(HEAD に全内容が残っている)。

### コンパイルエラーの内訳(import 修正後の 35 件)

**恒久バグ(ツールチェーン非依存 — 旧環境でもコンパイル不能だった)**:
- `chord_node_to_string` / `option_to_string` の二重定義(chord_parser.mbt:382,427 と parser.mbt:96,142)
- `lexer.mbt` `group_by_lines` 内の `current_line` が非 `mut` なのに再代入

**現行 core(0.7.2)との API ドリフト**:
- `String::substring` のラベル引数化(位置引数呼び出しが 6 件)
- `s[i]` が `UInt16` を返すようになり `Char` と不一致(7 件)
- `String::index_of` が消滅 → `find`(`Int?` 返し)に
- `starts_with` → `has_prefix`
- 構造体リテラルが `Type::{...}` 構文に(7 件)
- match 腕の `_ => {}` が空 Map リテラルに解釈される(8 件)
- `Buffer` から `write_char` / `to_string` が消滅(代替: builtin の `StringBuilder`)

### 実装済み機能(HEAD、ロジックレベル)

アクシデンタル s/b、ディグリー 1–7、m/dim/aug、セブンス優先順位(M7 → 7 → 6 → add、2 桁 add11/13 を先にチェック)、括弧外 b5/sus(2/4/6 検証つき)、括弧内オプション(空括弧・カンマ不正検出)、スラッシュベース(アクシデンタル任意・ディグリー必須)、行/小節線の字句解析、行番号付きエラー、手組み JSON 出力、wasm_api(parse_to_json / get_version / health_check)。

---

## 2. ビルド失敗の原因と修復方針

### 直接原因

`src/moon.pkg.json` の import が `"@moonbitlang/core/buffer"` と**先頭 `@` 付き**で記述されている。import パスに `@` は使えない(`@` はソースコード内のエイリアス記法)。`@` を外せば解決エラー自体は消えることを再現実験で確認済み。core 側には buffer パッケージが存在する(`~/.moon/lib/core/buffer`、core 0.7.2)。

### 推奨する修復

`@` を外すだけの対処ではなく、**buffer 依存自体を削除する**:

- `@buffer` の使用箇所は HEAD の `lexer.mbt:32` の `@buffer.new()` 1 箇所のみ
- 現行 core では `Buffer` から `write_char` / `to_string` が消えており、どのみち書き換えが必要
- builtin の `StringBuilder` に置換すれば外部 import が不要になり、問題が根本消滅する

あわせて `moon.mod.json` に `"source": "src"`(import パスが `seo1nk/chord_language` に短縮される)と `"preferred-target": "js"` を追加し、`src/moon.pkg.json` の非正規な `wasm-export` / `wasm-import` キー(現行 moon のリンク設定ではない)を `link.js.exports` 形式へ移行する。markdown.mbt の `src/api/moon.pkg` が雛形になる。

### ツールチェーン固定

moon 0.1.20260119 / moonbitlang/core 0.7.2(2026-07-03 時点)。String 系 API のラベル引数化・StringView 化が直近も進行しており、ドリフト再発リスクがある。バージョンを README または AGENTS.md に固定記録し、markdown.mbt フォークと同一ツールチェーンで整合確認する運用を敷く。

---

## 3. markdown.mbt 統合ポイント分析

markdown.mbt は chord DSL 統合に必要なフックを**既にほぼ備えている**。汎用プラグイン機構(TODO.md の「Custom syntax extensions」)は未実装だが、それを待つ必要はない。

### 経路 1: ライブプレビュー(JS 側) — 改造ほぼゼロ

- `playground/ast-renderer.tsx:79-87` に `CodeBlockHandler` / `RendererOptions.codeBlockHandlers` という言語キーのカスタム JSX レンダラ機構が実装済み
- `playground/PreviewPane.tsx:44-66` に `svg` と `moonlight-svg` の実例があり、`"chord"` ハンドラは同型で登録できる
- handler が null を返すと通常ハイライトへフォールスルー(ast-renderer.tsx:236-249)
- `parseCodeBlockLang`(ast-renderer.tsx:52)は `chord:compact` のようなモードサフィックスも解釈できる

**注意**: `ast-renderer.tsx` は npm パッケージ `@mizchi/markdown` の exports に含まれない playground 内部コード。ブログ本体で使うにはフォークでパッケージ export に昇格させる必要があり、本家追従コストが恒常的に発生する(→ Phase 6 のフォーク差分ドキュメントで緩和)。

### 経路 2: SSR / 静的 HTML(MoonBit 側) — 小改造が必要

- `src/renderer.mbt:38-51` の `Block::FencedCode` 分岐が唯一のフック地点。info の先頭語を `class="language-{lang}"` にして `<pre><code>` 固定出力する
- `src/plugin.mbt` の `RenderOptions.code_highlighter`((CodeBlockInfo, String) -> String)は**定義だけあって `render_html` に未配線**(使用箇所は experimental/tui のみ)。SSR で chord を描画するには、`renderer.mbt` に `info == "chord"` の直接分岐を足すか、RenderOptions を `render_html` に貫通させる改造が必要

### 依存の取り方

- moon のパス依存 `"deps": {"seo1nk/chord_language": {"path": "../chord-language"}}` が解決できることを実験で確認済み(moon 0.1.20260119)
- ただしパス依存は CI・Cloudflare ビルド環境で壊れるため、公開時までに mooncakes.io publish か monorepo 化が必要

### インクリメンタルパースとの相性

`src/incremental.mbt` の `find_affected_range` はブロック配列単位で前後ブロックを再利用する。fenced code block は `block_parser_code.mbt` で閉じフェンスまで一括読取される 1 個の `Block::FencedCode` なので、**chord ブロックは自然に再パース単位となり、markdown.mbt のパーサは無改造で済む**。chord ブロック外の編集で chord ブロックが再パースされないことも構造上保証される。

### エディタの制約

`frontend/editor/literal-markdown-editor.ts:692-709` の `highlightedCodeInnerHtml` は `stripHtml(結果) === source` というロスレス不変条件を強制する。つまり **literal エディタ内でのコード譜のグラフィカル描画は原理的に不可能**。リッチ表示はプレビューペイン(AST → JSX)側に限定される。ブログのエディタ構成は `SyntaxHighlightEditor` + `PreviewPane` 方式に一本化するのが正しい。

### エディタ内シンタックスハイライトの追加手順

1. `src/highlight_chord/` パッケージ新設(`highlight_common.tokens_to_html` を再利用。`src/highlight_moonbit/` が 3 行実装の実例)
2. `frontend/highlight/languages/chord.ts` を追加
3. `frontend/highlight/types.ts` の `highlightLanguages` / `languageAliases` に `"chord"` を追加
4. `package.json` の imports(`#moonbit/highlight-chord`)・exports(`./highlight/chord`)・files の 3 箇所に追記

### デプロイ構成

`wrangler.jsonc` + `worker/index.ts` は playground/dist を ASSETS バインディングで静的配信するだけの SPA 構成。vite build に乗れば chord 追加によるデプロイ設定変更は不要。

---

## 4. アーキテクチャ決定の分析

roadmap.md の決定ポイント D1〜D9 の根拠。

### D1: HTML レンダラは MoonBit 側に置く(推奨)

| | MoonBit 側(推奨) | JS 側 |
|---|---|---|
| SSR とプレビューの整合 | 同一出力を共用(単一ソース) | 描画ロジックが二重化 |
| 実装コスト | MoonBit での文字列生成 | JSON から DOM 構築、JSX と親和 |
| インタラクティブ UI | トグル等は JS 側で HTML に後付け | 自由 |

SSR(ブログ本番)とライブプレビューの両経路で同じ HTML を出すことが品質保証の要になるため、MoonBit 側 `render_html` を単一ソースとし、数字 ⇄ 実音トグルのようなインタラクションは生成 HTML に対する JS の振る舞いとして足す。

### D2: 統合方式は fenced code block + info 文字列(推奨)

3 案の比較:

- **(a) fenced code block + info 文字列**(採用): 境界明確・内容不透明なコンテナとして chord に十分。インクリメンタルパース無改造、mdast 互換維持、フォーク差分最小
- **(b) JS 側後処理**: mdast の `{type:"code", lang:"chord"}` を歩いて変換。プレビューはこれで良い(codeBlockHandlers がまさにこれ)が、SSR は MoonBit 側なので結局 (a) の配線が要る
- **(c) 新 Block 型を CST に追加**: `types.mbt` の Block enum 変更が block_parser / serializer / renderer / renderer_literal / json_ast / incremental の全 match 分岐に波及し、mdast 互換(js/api.d.ts は @types/mdast 再エクスポート)も崩れる。**不採用**

実運用はハイブリッド: プレビュー = (b) の codeBlockHandlers、SSR = (a) の renderer.mbt 配線。どちらも chord-language の同じ `render_html` を呼ぶ。

### D3: 削除ファイルは「復元して選別」

`ast.mbt`(型定義)と `parse_error.mbt`(エラー体系)は設計が仕様に忠実で健全なため土台として採用。`lexer.mbt` / `chord_parser.mbt` は 35 エラーの大半を占め、現行 MoonBit では StringView / パターンマッチベースの書き方が大幅にクリーンになるため、参照実装として復元した上で Phase 3 で書き直す。

### D4: エラー回復は行単位から

fail-fast(最初のエラーで全体中断)はライブプレビュー用途に不適。行単位でエラーを収集し部分 AST を返す設計に変える。行内トークン単位の回復(1 行に複数エラー+残りのコードを描画)はパーサ複雑度が跳ねるため、エディタの squiggle 体験が必要になった時点で判断する。

### D5: 配布は mooncakes.io publish が第一候補

パス依存は CI・Cloudflare で壊れる。publish が何らかの理由でできない場合は monorepo 化(フォークに chord-language を取り込む)がフォールバック。決定は Phase 4 末、実施は Phase 6。

### D6: SSR 配線は RenderOptions の貫通が本命

`renderer.mbt` への `info == "chord"` 直接分岐は最速だが chord 専用のフォーク差分になる。`RenderOptions.code_highlighter`(既に定義済み・未配線)を `render_html` に配線する形なら汎用機構の完成であり、本家へ upstream できる可能性すらある。Phase 2 の検証結果を見て確定する。

### D7: キー指定の記法 — 決定済み(2026-07-03、フロントマター方式)

ユーザー決定により、Markdown の info 文字列(` ```chord key=G `)ではなく**ブロック内フロントマター**(`---` / `key: G` / `---`)を採用した(仕様 v1.2)。根拠: (1) ブロックが自己完結し、Markdown の外(DSL 単体利用)でも成立する、(2) Obsidian の abcjs プラグインがブロック先頭のインライン JSON でオプション指定する確立された前例に沿う、(3) 将来フィールド(`title` / `tempo` 等)の拡張余地がある。

### D9: 移調機能のスコープ — 決定済み(2026-07-03)

ディグリー ⇄ コードの**タブ切替**と、コードタブでの**キープルダウンによる任意キー移調**まで Phase 4 のスコープとする(仕様 v1.2 の表示仕様)。変換は AST → 表示の純関数としてパーサから独立させる。クライアント側の再レンダリングも chord-language の JS ビルド(MoonBit 製)を呼ぶことを推奨 — 変換ロジックを JS 側に二重実装すると SSR との単一ソース性が壊れるため(新決定ポイント D13)。

### D8, D10〜D13

roadmap.md の表を参照。いずれも「実装が仕様を先回りして固定しない」ことを原則に、方向付け(仕様書への記録)と実装時期を分離している。

---

## 5. 仕様 v1.0 と実装の乖離

Phase 3 で解消すべき既知の不整合:

1. **DuplicateSeventh 未検出**: `parse_error.mbt:119` の `duplicate_seventh_error` は定義のみで未使用。`1M77` / `17M7` は仕様どおりの DuplicateSeventh ではなく UnrecognizedToken になる
2. **InvalidQuality の発生経路なし**: 不正クオリティは末尾の UnrecognizedToken に落ちる
3. **`ParseError.position` 未設定**: フィールドはあるがどこからも設定されず line のみ。エディタでのエラー箇所ハイライトの前提が欠けている
4. **`ParseError::syntax` と `semantic` が実装同一**: エラー分類フィールドがなく区別が無意味
5. **`sus11` の誤分類**: `parse_single_option` が length()==4 を要求するため InvalidSusDegree ではなく InvalidTension になる
6. **括弧内空白の字句衝突**: lexer が空白でトークン分割するため `1M7(b9, s11)` はトークンが割れて UnmatchedParenthesis になる。一方 chord_parser 側は trim() しており仕様の疑似コードも空白許容を示唆 — 仕様に括弧内空白の可否が未定義
7. **仕様書の内部矛盾**: `docs/chord.md:233` の正規表現が `sus[1-7]` を許すが、本文と AST 定義は 2/4/6 のみ
8. **コメント構文が未定義**: 仕様書の構文例(`docs/chord.md:53-56` 等)が `#` コメントを多用しているのに、コメント構文は仕様にも実装にもない(例をそのまま入力するとエラー)
9. **wasm_api の JSON エスケープ不備**: `parse_to_json` のエラー JSON は `"` のみエスケープし、バックスラッシュ・制御文字は未処理(不正 JSON を生成しうる)。エラーも フラットな文字列のみで kind/line/position の構造化なし → `derive(ToJson)` + `@json` への刷新で一括解消

---

## 6. 仕様自体の穴(将来拡張)

コード譜 DSL として将来必要になる要素で、v1.0 に欠けているもの(優先順は roadmap.md Phase 5 参照。版番号は 2026-07-03 の再編後):

- **色アノテーション** → **v1.1 として策定・実装済み**(2026-07-03、Phase 1)
- **キー指定**(ディグリー記譜を実音表示するには必須)→ **v1.2 として仕様策定済み**(2026-07-03、フロントマター方式+タブ表示+キープルダウン。実装はパースが Phase 3・表示が Phase 4)
- **セクションラベル**(`[Verse]` 等)→ v1.3
- **リピート記号・ボルタ**(`|:`, `:|`, `|1`, `:|2`, `%` 等)→ v1.3(語彙は ChordPro grid を正として Phase 3 で予約)
- **N.C. / 休符・終止線** → v1.3
- **拍子・小節内リズム配置**(ChordMark のデュレーションドット式が手本)→ v1.4 以降
- **歌詞対応** → v1.4 以降(記法方向は v1.3 策定時に決定)
- 細部未定義: 空入力の扱い(現実装は Ok(0 行))、括弧外での b5 と sus の共存可否、ダブルフラット/シャープ

---

## 7. テストカバレッジの穴

既存 13 テストは基本形 / 小節線 / 複数行 / 複雑コード / ベース有無 / エラー 4 種(InvalidDegree, EmptyParentheses, MissingBassDegree, InvalidSusDegree)/ JSON 出力 / 仕様例 / 空白タブ / add9-13 のみ。仕様の表・エラー一覧に対して以下が未テスト:

- 成功系: `1M7b5` / `1sus4`(括弧外)、`1M7b5(b9)`(混在)、`1/b3`(ベースのアクシデンタル)、`17` vs `1M7`(優先順位)、`16` / `36`(Sixth)、`dim7` / `aug`、`add2` / `add4` / `add6`
- エラー系: `1(,b9)` 等カンマ不正、括弧不一致、不正テンション、`1M77` セブンス重複、空入力

Phase 3 で「仕様とテストの対応表」を作り、`docs/chord.md` の全行にテストを対応づけて客観化する。

---

## 8. 先行事例調査

### ChordPro — 小節線記法の語彙の正

`{directive}` + 歌詞内 `[コード]` + `#` コメントという構造。**grid 環境**が小節線ベース記法の最も体系的な先行例: `|`(単)、`||`(複)、`|.`(終止)、`|:` `:|`(リピート)、`|1` `:|2`(ボルタ)、`%`(前小節リピート)、`.`(空セル)。本 DSL の小節線拡張はこの語彙を正として予約する。
出典: https://www.chordpro.org/chordpro/directives-env_grid/

### ChordSheetJS — API 設計の手本

複数パーサ(ChordPro / ChordsOverWords / UltimateGuitar)が共通の Song → Line → ChordLyricsPair モデルを生成し、Text / HtmlTable / HtmlDiv / Pdf の各フォーマッタが整形する**完全なパーサ/フォーマッタ分離**。CSS は `HtmlTableFormatter.cssString('.scope')` のスコープ付き取得。さらに**ナッシュビル数字を直接サポート**: `Chord.parse('2/4').toChordSymbol('E').toString()` → `'F#/A'`。本 DSL の実音変換の直接の参照実装。
出典: https://github.com/martijnversluis/ChordSheetJS

### tonal.js — 移調の部品

`Progression.fromRomanNumerals('C', ['IMaj7','IIm7','V7'])` → `['CMaj7','Dm7','G7']`。ディグリー列 + key → 実コード列の変換ロジックの参照実装。
出典: https://github.com/tonaljs/tonal

### NNS アプリ(JotChord / 1Chart / Chord Sheet Maker Online)— UX の手本

JotChord: プレーンテキストで NNS を打つとチャートが逐次更新(本プロジェクトの目標体験)。記譜慣習: 単独数字 = 1 小節フル、マイナーは `6-`/`6m`、マイナーキーは相対長調で記譜。Chord Sheet Maker Online: **文字コード ⇄ 数字表示の切替機能**(読者向けトグル UI の実証例)。
出典: https://www.jotchord.com/what-is-the-nashville-number-system-nns-chord-chart

### ChordMark — 将来のリズム・歌詞拡張の手本

コード行と歌詞行を分離し、デュレーションドット(`A..` = 2 拍)から小節線を自動レンダリング、歌詞側は `_` マーカーでコード位置指定、`#v`/`#c` セクション自動採番。「同一ソースから歌詞+コード版とコードグリッド版の両方を描画」という発想はブログの表示モード切替に転用できる。
出典: https://chordmark.netlify.app/docs/getting-started

### Markdown 統合の UX パターン

Obsidian の abcjs プラグイン(` ```abc ` フェンスブロック+先頭インライン JSON でオプション)、markdown-it-chords(歌詞中 `[C]` を `<span class="chord">` に変換)。**fenced code block + 言語タグ+属性**が確立パターンであり、` ```chord key=G ` はこれに乗る。
出典: https://github.com/abcjs-music/obsidian-plugin-abcjs

### 調査で判明したリスク

小節線グリッド(歌詞なしコード譜)の Web 向け HTML/CSS 実装は一次資料が薄い。ChordSheetJS は「歌詞の上にコード」型が主、ChordPro grid は PDF 出力、NNS アプリは非 OSS。**小節グリッドの CSS は自前設計になる**前提で、早期の目視反復(スタンドアロンプレビューページ)を計画に組み込んだ。

---

## 9. リポジトリ運用方針

- **chord-language**(本リポジトリ): DSL 仕様書・パーサ・HTML レンダラ・JS エクスポート。単体 CI を Phase 1 で導入
- **markdown.mbt フォーク**(Phase 2 で作成): renderer.mbt の chord 配線、codeBlockHandlers 登録、highlight_chord、ブログ基盤。フォーク差分はドキュメントで一覧管理し、本家更新の取り込み手順を Phase 6 で整備
- **ライセンス**: chord-language は Apache-2.0、markdown.mbt は MIT。フォーク公開時に併記・NOTICE 整理
- **バージョン管理**: DSL 仕様書(docs/chord.md)にバージョンを付与し、実装・テスト・仕様の三者一致を各フェーズの完了条件で担保する

---

## 10. 戦略選定の経緯

ロードマップ策定にあたり、3 つの戦略軸で独立にロードマップ案を立案し、2 つの審査観点で採点した。

### 3 案の概要

| 案 | 戦略 | 要旨 |
|---|------|------|
| A | ライブラリ先行完成 | chord-language 単体をパーサ+レンダラ+公開まで完成させてから統合する堅実なボトムアップ |
| B | **垂直スライス**(採用) | 最短で「` ```chord ` → ブラウザ表示」の端到端を通し、動くものを見ながら反復 |
| C | プロダクト逆算 | ブログの最終体験を文書で固定し、体験の縦切りスライスとして刻む |

### 審査結果

| 案 | ソロ開発の実行可能性 | プロダクト価値・アーキテクチャ健全性 |
|---|---|---|
| A | 6.5 / 10 | 6.5 / 10 |
| **B** | **8.5 / 10** | **8.5 / 10** |
| C | 7 / 10 | 7.5 / 10 |

**案 B が勝者となった理由**:
- 端到端を Phase 2 で最小コストで成立させ、統合仮定(codeBlockHandlers・パス依存・インクリメンタルパース無改造)を早期に実地検証できる
- 最大の技術リスク(fail-fast 廃止を含むパーサ全面書き直し)を、動くプレビューという回帰検出器を得てから実施する順序が合理的
- 設計判断のタイミングが適切: レンダラ配置と統合方式は Phase 2 着手前に決定(必要十分な早さ)、パーサ書き直し・CSS はフィードバック付きで確定(遅すぎない遅延)。案 A の「利用者が現れる前の API 凍結」も、案 C の「統合フィードバックなしのメガフェーズ」も避けている

**案 A の弱点**: 唯一の利用者(フォーク)が API を使う前に v0.1.0 を凍結・公開する「早すぎる固定」。端到端の成立が最も遅く、ブログという成果が長期間見えないためソロ開発の完走確率を下げる。

**案 C の弱点**: Phase 2 が「全面書き直し+レンダラ+仕様整合」の一枚岩で、統合フィードバックなしに潜り切る必要がありスコープ膨張リスクが単一フェーズに集中する。

### 採用した移植アイデア(敗者案から)

最終ロードマップは案 B を骨格に、両審査が挙げた以下の要素を移植して弱点を補った:

**案 A から**:
1. Phase 1 の完了条件を「13 テスト全パス」から「テストが実行できる」に緩和(失敗は Phase 3 書き直しの入力とする)— 捨てる予定のコードへのパッチ投資を防ぐ
2. chord-language 単体 CI の Phase 1 導入(パス依存を持たない単体なら今すぐ組める)— CI レス期間 5 フェーズという案 B 最大の運用弱点を解消
3. 配布方式の「決定」を Phase 4 末に前倒し(実施は Phase 6 のまま)
4. スタンドアロン HTML プレビューページの常設(CSS 反復の場)
5. 「仕様とテストの対応表」を Phase 3 の完了条件に採用
6. ツールチェーンバージョンの固定記録
7. 公開品質ゲート(クリーン環境ビルド・README コピペ検証・v0.1.0 タグ+CHANGELOG)を Phase 6 に組み込み

**案 C から**:
1. 軽量な体験仕様書(筆者/読者/演奏者の 3 ジャーニー+MVP スコープ)を Phase 1 に追加し、各フェーズの完了条件から参照 — 「動く画面」基準を補完し、読者価値の抜けを早期検出
2. 読者向け数字 ⇄ 実音トグル UI を Phase 4 の明示的成果物に
3. フォーク差分ドキュメント+本家追従の運用手順を Phase 6 に追加 — 1 人で 2 リポジトリを長期保守するための唯一の持続可能性対策
4. キー指定の記法論点(info 文字列 vs DSL 内ディレクティブ)を決定ポイント D7 に採用
