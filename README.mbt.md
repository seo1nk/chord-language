# seo1nk/chord_language

数字ディグリー記譜法（ナッシュビル・ナンバー・システム系）のコード譜 DSL。MoonBit 製のパーサ・HTML レンダラ・移調エンジン・再生スケジューラを含み、JS ターゲットにコンパイルしてブラウザで使う。

仕様書: [docs/chord.md](docs/chord.md)（v1.0）

## 記法の例

```
---
key: Eb
bpm: 96
---
[サビ]
| 1(9) b3@red 2m 37 |
> の記憶 が_すべ て消えて も
| 6m7 3m/5 4m 2-5 |
```

- ディグリー（`1`〜`7`、シャープは `#`/`s`、フラットは `b`）+ クオリティ・セブンス（`M7`/`maj7`）・テンション・スラッシュベース
- `|` 小節線、`%` 反復、`_` 空拍、`NC`、`-` グループ（1 スロット複数コード）、`@red` 強調色
- `[名前]` セクションラベル、`>` ペア歌詞行
- フロントマターで `key` / `bpm` / `time`（拍子）

## 公開 API（JS ターゲット）

```js
import {
  parse_to_json,      // {success, data, errors} の JSON
  parse_to_html,      // ディグリー表示のスコア HTML
  parse_to_notes_html, // 指定キーの実音表示 HTML
  render_widget_html, // タブ・キー選択・再生・画像コピー付きウィジェット HTML
  inline_chord_html,  // 単一コード記号のインライン HTML（:2m7: 記法用。不正なら ""）
  parse_to_playback,  // 再生スケジュール JSON（bpm/totalBeats/events/bass/stabs/cursor）
  chord_css,          // スコープ付き CSS（ページに 1 回注入）
} from "./_build/js/release/build/chord_language.js";
```

各関数の入出力・フォールバック挙動・Markdown 側（markdown.mbt フォーク）からの統合手順（SSR / プレビュー / クライアントランタイム / ウィジェット DOM コントラクト）は **[docs/api.md](docs/api.md)** を参照。

## 開発

```bash
moon check                 # 型チェック
moon test                  # テスト（moon test --update でスナップショット更新）
moon build --target js --release   # JS ビルド
moon info && moon fmt      # インターフェース更新・整形
```

開発用プレビュー: `moon build --target js --release && python3 -m http.server 8080` して `http://localhost:8080/tools/preview.html`。

Markdown への統合（`:::` ブロック）は [seo1nk/markdown.mbt](https://github.com/seo1nk/markdown.mbt)（フォーク。本リポジトリを submodule として取り込み）を参照。

## ドキュメント

- [docs/chord.md](docs/chord.md) — 言語仕様（v1.0）
- [docs/api.md](docs/api.md) — API 仕様書（公開 API と Markdown 側からの呼び方）
- [docs/spec-test-matrix.md](docs/spec-test-matrix.md) — 仕様とテストの対応表
- [docs/roadmap.md](docs/roadmap.md) / [docs/development-plan.md](docs/development-plan.md) — 開発ロードマップ（歴史的文書）
- [docs/product-experience.md](docs/product-experience.md) — プロダクト体験仕様

## License

Apache-2.0
