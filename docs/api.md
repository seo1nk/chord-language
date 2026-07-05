# API 仕様書

chord-language が公開する API と、Markdown 側（markdown.mbt フォーク）からの呼び方を定義する。言語仕様そのものは [chord.md](./chord.md) を参照。

- 対象バージョン: 1.0.0
- JS ビルド成果物: `_build/js/release/build/chord_language.js`（ESM。`moon build --target js --release` で生成）

## 設計原則

**音楽的な計算はすべて chord-language（MoonBit）側の単一ソース。** パース・ローマ数字変換・移調（異名同音のスペリング）・再生スケジュール（MIDI ノート・拍割り付け・`%` の解決）は本ライブラリが行い、呼び出し側（Markdown 側の JS）は **DOM 操作と Web Audio の発音だけ**を担当する。移調や音高計算を JS 側で再実装してはならない。

---

## 1. 公開 API リファレンス（JS ターゲット）

```js
import {
  parse_to_json,
  parse_to_html,
  parse_to_notes_html,
  parse_to_playback,
  render_widget_html,
  chord_cheatsheet_html,
  chord_css,
  get_version,
  health_check,
} from ".../chord_language.js";
```

すべての関数は同期・純粋（DOM や環境に触れない）で、入力の `input` は `:::` フェンスの**内側のテキスト**（フロントマターを含む。フェンス行は含まない）。

### `parse_to_json(input: string): string`

パース結果の JSON 文字列を返す。

```jsonc
{
  "success": true,            // errors が空かどうか
  "data": { /* ScoreAST */ }, // 部分 AST（エラー行は除外）
  "errors": [                 // 構造化エラー（行番号順とは限らない）
    { "kind": "InvalidDegree", "message": "...", "line": 2, "position": 0, "token": "8x" }
  ]
}
```

- `data`（ScoreAST）の形状・`kind` の一覧は [chord.md の AST 定義・エラーハンドリング](./chord.md#ast-定義)を参照
- `position` はコード行由来のエラーのみ（フロントマター・歌詞行のエラーには無い）
- 用途: エディタ連携（エラー位置表示）、独自レンダリング、ツール類

### `parse_to_html(input: string): string`

**ディグリー表示**（ローマ数字 + ♭/#）のスコア HTML を返す。エラー行は元の行位置にメッセージ + ソース行として埋め込まれ、正しい行は描画される。

- ルート要素: `<div class="chord-score" style="--chord-cols:N">...`
- スタイルは `chord_css()` の注入が前提

### `parse_to_notes_html(input: string, key: string): string`

指定キーの**実音表示**スコア HTML を返す。キー変更（移調）時の再描画に使う。

- `key`: `"C"` `"F#"` `"Bb"` などのメジャーキー名
- **フォールバック**: パースエラーがある場合はディグリー表示（エラー埋め込み）を、`key` が不正な場合はディグリー表示を返す

### `render_widget_html(input: string): string`

タブ（ディグリー/コード）・キープルダウン・再生・画像コピーの UI を備えた**ウィジェット HTML** を返す。SSR とライブプレビューの両方でこの単一ソースを使うこと（DOM 構造は後述の「ウィジェット DOM コントラクト」）。

- 初期キーはフロントマターの `key`（未宣言なら `C`）。宣言キーが一覧と異名同音の場合、プルダウンのそのスロットを宣言の綴りで置き換える
- **フォールバック**: パースエラーがある場合はウィジェット（タブ等）なしのエラー埋め込みスコアを返す

### `parse_to_playback(input: string, key: string): string`

再生スケジュールの JSON 文字列を返す。**拍の単位は 4 分音符**（`spb = 60 / bpm` 秒）。

```jsonc
{
  "bpm": 120,        // フロントマターの bpm（既定 120）
  "totalBeats": 8,   // 総拍数（4 分音符換算）
  "events": [        // 上声（コードの構成音）。1 スロット = 1 小節を持続
    { "beat": 0, "dur": 4, "notes": [67, 71, 74] }   // notes は MIDI ノート番号
  ],
  "bass": [          // ベーストラック。拍ごとの刻み（プラッキーに発音すること）
    { "beat": 0, "dur": 1, "note": 43, "gain": 1 }   // gain = 相対音量（省略時 1）
  ],
  "stabs": [         // 複合拍子(x/8)の弱拍 = 上声和音の短い刻み（単純拍子では空配列）
    { "beat": 0.5, "dur": 0.5, "notes": [67, 71, 74] }
  ],
  "cursor": [        // 再生ハイライト用。cell は表示パネル内の .chord-cell の文書順インデックス
    { "beat": 0, "dur": 4, "cell": 0 }
  ]
}
```

- `key` が不正な場合はフロントマターの `key`（無ければ `C`）にフォールバック
- パースエラーのある行は再生からも除外される（`events` / `bass` / `cursor` に現れない）
- `%` の解決・`_` の持続・N.C. の無音・グループの等分割・拍子によるスロット長とベースの刻み・複合拍子の「ずんちゃっちゃ」（ずん = `bass`、ちゃっちゃ = `stabs`。[chord.md の再生仕様](./chord.md#再生仕様)）は**この関数がすべて解決済み**。呼び出し側はスケジュールをそのまま鳴らせばよい（`gain` はベース音量の乗数、`stabs` は持続和音より強いアタックで短く発音する）

### `chord_cheatsheet_html(): string`

記法チートシートの HTML（`.chord-cheatsheet`。スタイルは `chord_css()` に含まれる）を返す。**埋め込み場所は呼び出し側が決める** — フォークのプレイグラウンドではエディタのヘッダの `?` ボタンから開くモーダルに表示している。末尾に 2-5-1 のコピー用スニペット（`::: … :::`）を含む。

### `chord_css(): string`

表示用 CSS を返す。すべて `.chord-` プレフィックスにスコープされている。**ページに 1 回だけ** `<style>` として注入すること（ウィジェットごとに注入しない）。

- テーマ: `--chord-bg` 変数を `:root[data-theme="dark"]` と `prefers-color-scheme` の両方で解決するため、ライト/ダークに自動追従する

### `get_version(): string` / `health_check(): string`

パッケージバージョン（`"1.0.0"`）/ 疎通確認（`"OK"`）。

## 2. MoonBit API（パッケージとして import する場合）

フォークの MoonBit コード（SSR 経路）からは、パッケージ import で直接呼べる:

| 関数 / 型 | 説明 |
|-----------|------|
| `parse(input : String) -> ParseResult` | `ParseResult { score : ScoreAST, errors : Array[ParseError] }` |
| `render_widget_html(input : String) -> String` | SSR で使うのは基本これだけ |
| `parse_to_html` / `parse_to_notes_html` / `parse_to_playback` / `chord_cheatsheet_html` / `chord_css` | JS 版と同一 |
| `ScoreAST` / `Line` / `Token` / `ChordNode` / `ParseError` ほか | AST 型（[chord.md](./chord.md#ast-定義) の TS 型に対応） |

---

## 3. Markdown 側からの呼び方（markdown.mbt フォーク統合）

統合の全体像: **`:::` フェンス → ウィジェット HTML は MoonBit 単一ソース、動的挙動はクライアントランタイム**。

```
                        ┌─ SSR (md_to_html) ──── renderer.mbt が
:::フェンス ── パース ──┤                        render_widget_html() を呼ぶ
                        └─ ライブプレビュー ──── mdast lang="chord-block" →
                                                codeBlockHandlers が
                                                render_widget_html() を呼ぶ
        どちらの HTML にも chord-widget が入り、クライアントランタイム
        (chord-widget.ts) がタブ・移調・再生・画像コピーを動かす
```

### 3.1 SSR 経路（MoonBit）

1. ローカル依存は **`moon.work` ワークスペース**で解決する（moon.mod の DSL 形式はパス依存を書けないため。フォークは本リポジトリを `chord-language/` に submodule として取り込んでいる）。フォークのルートに `moon.work`:
   ```toml
   members = [
     ".",
     "./chord-language",
   ]
   ```
   さらにフォークの `moon.mod` の import にバージョン付きで宣言する（ワークスペースのメンバーがこの版を満たす）:
   ```
   "seo1nk/chord_language@1.0.0",
   ```
2. `src/moon.pkg` に import を追加:
   ```
   "seo1nk/chord_language" @chord_language,
   ```
3. `renderer.mbt` の `Block::FencedCode` 分岐で、**Colon フェンスのとき**にウィジェットを出力:
   ```moonbit
   if fence_marker is FenceMarker::Colon {
     buf.write_string(@chord_language.render_widget_html(code))
     buf.write_char('\n')
     return
   }
   ```
   （` ``` ` フェンスは言語タグに関わらず通常のコードブロックのまま）

### 3.2 ライブプレビュー経路（JS）

1. `src/api/json_ast.mbt` が Colon フェンスを mdast の `{type: "code", lang: "chord-block"}` にマップする（言語タグとしての `chord` と衝突させないための専用キー）
2. プレビューの `codeBlockHandlers` に `chord-block` ハンドラを登録し、`render_widget_html` の HTML を挿入:
   ```tsx
   "chord-block": {
     render: (code, span, key) => (
       <RawHtml key={key} data-span={span} html={render_widget_html(code)} />
     ),
   },
   ```

### 3.3 CSS の注入（両経路共通・1 回だけ）

```ts
const style = document.createElement("style");
style.textContent = chord_css();
document.head.appendChild(style);
```

### 3.4 クライアントランタイム

参照実装: フォークの `playground/chord-widget.ts`（document への委譲イベントで実装しているため、ページに 1 回 `installChordWidgets()` を呼ぶだけで SSR ページ・プレビューの両方で動く）。ランタイムの責務は次の 4 つ:

| イベント | 処理 |
|---------|------|
| `.chord-tab` クリック | `widget.dataset.chordActive` を `"degree"` / `"notes"` に切替え、`.chord-tab--active` クラスを付け替える（パネルの表示切替は CSS が行う） |
| `.chord-key-select` 変更 | `widget.dataset.chordKey` を更新し、`.chord-panel--notes` の innerHTML を `parse_to_notes_html(src, key)` で差し替える（再生中なら停止） |
| `.chord-play` クリック | `parse_to_playback(src, key)` のスケジュールを Web Audio で発音（上声はサステイン、`bass` / `stabs` はプラッキーな刻み）。`cursor` に従い、表示中パネルの `.chord-cell`（文書順）に `.chord-cell--playing` を付けて移動。トグルで停止・完了で自動停止 |
| `.chord-copy-img` クリック | 表示中パネルの `.chord-score` を PNG 化してクリップボードへ（参照実装は SVG foreignObject + canvas。`chord_css()` を画像に埋め込む） |

`src` と `key` はウィジェットの data 属性から取得する（下記）。

### 3.5 ウィジェット DOM コントラクト

`render_widget_html` が生成する構造。**ランタイムはこの属性・クラスを規約として参照してよい**（変更時は本書を更新する）:

```html
<div class="chord-widget"
     data-chord-active="degree"     <!-- ランタイムが "degree"/"notes" に切替 -->
     data-chord-key="G"             <!-- 現在のキー。ランタイムが更新 -->
     data-chord-src="...">          <!-- ブロックの元テキスト（HTML エスケープ済み） -->
  <div class="chord-tabs" role="tablist">
    <button class="chord-tab chord-tab--active" data-chord-tab="degree">ディグリー</button>
    <button class="chord-tab" data-chord-tab="notes">コード</button>
    <select class="chord-key-select">…12 キー…</select>
    <button class="chord-play">▶ 再生</button>
    <button class="chord-copy-img">画像コピー</button>
  </div>
  <div class="chord-panel chord-panel--degree"> <div class="chord-score">…</div> </div>
  <div class="chord-panel chord-panel--notes">  <div class="chord-score">…</div> </div>
</div>
```

- パネルの表示/非表示・キー選択の可視性は `data-chord-active` に対する CSS（`chord_css()` 内）が制御する
- `cursor.cell` は**表示中パネル内**の `.chord-cell` を `querySelectorAll` した文書順インデックスに対応する（空セルを含む）
- パースエラー時は `chord-widget` を含まない `<div class="chord-score">…<div class="chord-line chord-error">…</div>…</div>` が返る

### 3.6 ビルドと配信

- chord-language はフォークに **git submodule**（`chord-language/`）として取り込まれており、フォークだけ clone すれば動く（`git clone --recursive`）
- フォークのルートで `moon build --target js --release` を実行すると、`moon.work` ワークスペースが**両モジュールをまとめて**ビルドする。成果物はワークスペースの `_build` にモジュール名で名前空間化される: `_build/js/release/build/seo1nk/chord_language/chord_language.js`（フォークの playground はこれを import する）
- 本リポジトリを**単体で**ビルドした場合（ワークスペース外）の成果物は従来どおり `_build/js/release/build/chord_language.js`
- **chord-language の API を変更したら JS を再ビルドしないとプレビューに反映されない**（症状: import エラーでページ全体が壊れる／古い挙動のまま）
- chord-language を更新したら、フォーク側で submodule のポインタを進めてコミットする（`cd chord-language && git pull && cd .. && git add chord-language`）

## 4. 互換性の約束

- `:::` ブロック内テキストの解釈は [chord.md](./chord.md)（v1.0）に従う。文法の破壊的変更はメジャーバージョンでのみ行う
- 公開 API の関数名・引数・JSON 形状（`parse_to_json` エンベロープ、`parse_to_playback` の `bpm/totalBeats/events/bass/stabs/cursor`）と、§3.5 の DOM コントラクトは互換性の対象
- `chord-score` 内部の細かい HTML 構造（セルの入れ子等）は互換性の対象外（スタイルは `chord_css()` を使うこと）
