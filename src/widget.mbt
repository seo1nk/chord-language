///|
/// コード譜ウィジェット（タブ・キー選択・再生・画像コピー UI）と、
/// その表示に使う CSS・記法チートシートの生成。
/// SSR とライブプレビューの両方がこの単一ソースを使う
/// （DOM 構造の契約は docs/api.md §3.5）。

///|
/// キープルダウンに載せるキー一覧（12 半音）。
/// 正準 12 キー表（transpose.mbt の canonical_key_names）から導出する
/// （相対転調のスペリングと同じ単一ソース。二重定義しない）
fn widget_keys() -> Array[String] {
  canonical_key_names()
}

///|
/// キー名の表示ラベル（b → ♭。# はそのまま）
fn key_display_label(key : String) -> String {
  key.replace_all(old="b", new="♭")
}

///|
/// キープルダウンの選択肢を組み立てる。
/// 宣言キーが一覧と異名同音（例: C# と Db）の場合は、そのスロットを宣言の綴りで置き換える
fn widget_key_options(initial_key : String) -> Array[String] {
  let keys = widget_keys()
  match parse_key_name(initial_key) {
    Some(ki) => {
      let pc = key_pitch_class(ki)
      let mut replaced = false
      for i in 0..<keys.length() {
        match parse_key_name(keys[i]) {
          Some(k2) =>
            if key_pitch_class(k2) == pc {
              keys[i] = initial_key
              replaced = true
              break
            }
          None => ()
        }
      }
      if !replaced {
        keys.push(initial_key)
      }
    }
    None => if !keys.contains(initial_key) { keys.push(initial_key) }
  }
  keys
}

///|
/// タブ（ディグリー / コード）とキープルダウンを備えたウィジェット HTML を生成する。
/// SSR とライブプレビューの両方がこの単一ソースを使う。
///
/// - デフォルトタブはディグリー
/// - コードタブの初期キーはフロントマターの key、未宣言なら C（既定値）
/// - キー変更・再生・画像コピーはクライアントランタイム（フォーク側
///   chord-widget.ts）が data 属性と公開 API（parse_to_notes_html /
///   parse_to_playback）を使って行う
/// - パースエラーがある場合はタブなしのエラー埋め込み表示を返す
pub fn render_widget_html(input : String) -> String {
  let result = parse(input)
  if !result.errors.is_empty() {
    return render_result_html(input, result)
  }
  let initial_key = result.score.key_or_default()
  let degree_panel = render_html(result.score)
  let notes_panel = match parse_key_name(initial_key) {
    Some(key_info) => render_notes_score_html(result.score, key_info)
    None => degree_panel
  }
  let sb = StringBuilder::new()
  sb.write_string(
    "<div class=\"chord-widget\" data-chord-active=\"degree\" data-chord-key=\"" +
    escape_html(initial_key) +
    "\" data-chord-src=\"" +
    escape_html(input) +
    "\">",
  )
  // タブとキープルダウン
  sb.write_string("<div class=\"chord-tabs\" role=\"tablist\">")
  sb.write_string(
    "<button type=\"button\" class=\"chord-tab chord-tab--active\" data-chord-tab=\"degree\">ディグリー</button>",
  )
  sb.write_string(
    "<button type=\"button\" class=\"chord-tab\" data-chord-tab=\"notes\">コード</button>",
  )
  sb.write_string("<select class=\"chord-key-select\" aria-label=\"キー\">")
  for k in widget_key_options(initial_key) {
    let selected = if k == initial_key { " selected" } else { "" }
    sb.write_string(
      "<option value=\"" +
      escape_html(k) +
      "\"" +
      selected +
      ">" +
      escape_html(key_display_label(k)) +
      "</option>",
    )
  }
  sb.write_string("</select>")
  // 再生・画像コピーはアイコンのみ(モバイルの幅でも並びが崩れないように)
  sb.write_string(
    "<button type=\"button\" class=\"chord-play\" title=\"表示中のキーで再生\" aria-label=\"再生\">" +
    play_icon_svg +
    "</button>",
  )
  sb.write_string(
    "<button type=\"button\" class=\"chord-copy-img\" title=\"表示中の譜面を画像としてコピー\" aria-label=\"画像コピー\">" +
    camera_icon_svg +
    "</button>",
  )
  sb.write_string("</div>")
  // パネル
  sb.write_string("<div class=\"chord-panel chord-panel--degree\">")
  sb.write_string(degree_panel)
  sb.write_string("</div>")
  sb.write_string("<div class=\"chord-panel chord-panel--notes\">")
  sb.write_string(notes_panel)
  sb.write_string("</div>")
  sb.write_string("</div>")
  sb.to_string()
}

///|
/// コード譜表示用の最小 CSS（.chord-score 配下にスコープ済み）。
/// リードシート風: コードは太字、小節線は縦線として描画する。
pub fn chord_css() -> String {
  (
    #|.chord-score { display: grid; grid-template-columns: repeat(var(--chord-cols), minmax(max-content, 1fr)); row-gap: 1.35em; line-height: 1.5; padding: 0.6em 0; --chord-cols: 4; --chord-barline: 1.5px solid rgba(136, 136, 136, 0.75); }
    #|.chord-line { grid-column: 1 / -1; display: grid; grid-template-columns: repeat(var(--chord-cols), minmax(max-content, 1fr)); align-items: stretch; }
    #|@supports (grid-template-columns: subgrid) { .chord-line { grid-template-columns: subgrid; } }
    #|.chord-cell { display: block; position: relative; padding: 0.25em 0.9em 0.25em 0.75em; min-height: 1.4em; min-width: 0; }
    #|.chord-cell--bar-before { border-left: var(--chord-barline); }
    #|.chord-line--start-bar .chord-cell:first-child { border-left: var(--chord-barline); }
    #|.chord-line--end-bar .chord-cell:last-child { border-right: var(--chord-barline); }
    #|.chord-score .chord { font-weight: 500; font-size: 1.06em; letter-spacing: 0.015em; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Hiragino Sans', 'Helvetica Neue', Arial, sans-serif; font-style: normal; white-space: nowrap; }
    #|.chord-inline { font-weight: 500; font-size: 0.95em; letter-spacing: 0.015em; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Hiragino Sans', 'Helvetica Neue', Arial, sans-serif; font-style: normal; white-space: nowrap; background: #8881; border: 1px solid #8883; border-radius: 4px; padding: 0.05em 0.4em; }
    #|.chord-cell.chord-group { display: flex; flex-wrap: wrap; align-items: baseline; column-gap: 0.5em; }
    #|.chord-cell.chord-group > .chord-lyric--split { flex: 1 0 100%; } /* パート数と不一致の拍分割歌詞はグループ全幅の行に */
    #|.chord-cell.chord-group > .chord { flex: 1 1 0; min-width: max-content; }
    #|.chord-repeat { opacity: 0.7; }
    #|.chord-nc { opacity: 0.85; }
    #|.chord-cell--blank .chord-lyric { margin-top: 1.55em; }
    #|.chord-widget, .chord-score { --chord-bg: #ffffff; }
    #|:root[data-theme="dark"] .chord-widget, :root[data-theme="dark"] .chord-score { --chord-bg: #0d1117; }
    #|@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) .chord-widget, :root:not([data-theme="light"]) .chord-score { --chord-bg: #0d1117; } }
    #|.chord-section { grid-column: 1 / -1; justify-self: start; font-size: 0.78em; font-weight: 700; letter-spacing: 0.06em; background: currentColor; border-radius: 3px; padding: 0.12em 0.7em; margin-bottom: -0.5em; }
    #|.chord-section-name { color: var(--chord-bg); }
    #|.chord-modline { grid-column: 1 / -1; justify-self: start; margin-bottom: -0.5em; }
    #|.chord-mod { display: inline-block; font-size: 0.68em; font-weight: 600; letter-spacing: 0.04em; border: 1px solid currentColor; border-radius: 3px; padding: 0.08em 0.45em; opacity: 0.8; white-space: nowrap; vertical-align: 0.1em; }
    #|.chord-cell .chord-mod { position: absolute; bottom: calc(100% - 0.15em); left: 0.6em; background: var(--chord-bg); z-index: 1; }
    #|.chord-score:has(.chord-cell .chord-mod) { padding-top: 1.5em; } /* 1 行目の小節上チップがスコア上端(タブ境界・PNG 書き出し範囲)からはみ出さないための余白 */
    #|.chord-cell .chord-mod--after { left: auto; right: 0.75em; }
    #|.chord-modline .chord-mod { font-size: 0.78em; font-weight: 700; letter-spacing: 0.06em; padding: 0.12em 0.7em; margin-right: 0.3em; }
    #|.chord-lyric { display: block; font-weight: 400; font-size: 0.72em; letter-spacing: 0; opacity: 0.88; margin-top: 0.15em; white-space: nowrap; }
    #|.chord-lyric--split { display: flex; } /* 断片中の - による拍分割(等幅カラム) */
    #|.chord-lyric-beat { flex: 1 1 0; min-width: 0; white-space: nowrap; }
    #|.chord--red { color: #d33636; }
    #|.chord--blue { color: #2563cc; }
    #|.chord--green { color: #1e9e50; }
    #|.chord-line.chord-error { display: flex; flex-direction: column; align-items: stretch; row-gap: 0.2em; border: 1px solid #d3363680; border-radius: 4px; padding: 0.4em 0.6em; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|.chord-error-msg { color: #d33636; font-size: 0.8em; }
    #|.chord-error-src { margin: 0; opacity: 0.75; white-space: pre-wrap; font-size: 0.9em; }
    #|.chord-widget { margin: 0.75em 0; border-bottom: 1.5px solid #88888866; padding-bottom: 0.6em; }
    #|.chord-tabs { display: flex; align-items: flex-end; gap: 0.3em; border-bottom: 1.5px solid #88888866; padding: 0 0.5em; flex-wrap: wrap; row-gap: 0.25em; }
    #|.chord-tab, .chord-key-select, .chord-copy-img, .chord-play { white-space: nowrap; }
    #|.chord-tab { font: inherit; font-size: 0.78em; padding: 0.3em 1.1em; border: 1.5px solid transparent; border-bottom: none; border-radius: 8px 8px 0 0; background: transparent; color: inherit; cursor: pointer; opacity: 0.6; margin-bottom: 0; }
    #|.chord-tab--active { opacity: 1; font-weight: 600; border-color: #88888866; background: var(--chord-bg); margin-bottom: -1.5px; }
    #|.chord-key-select { font: inherit; font-size: 0.78em; margin-left: auto; align-self: center; margin-bottom: 0.25em; background: transparent; color: inherit; border: 1px solid #8886; border-radius: 4px; padding: 0.05em 0.3em; }
    #|.chord-copy-img, .chord-play { font: inherit; font-size: 0.72em; align-self: center; margin-bottom: 0.25em; background: transparent; color: inherit; border: 1px solid #8886; border-radius: 4px; padding: 0.1em 0.6em; cursor: pointer; opacity: 0.75; }
    #|.chord-play { margin-left: 0.45em; }
    #|.chord-copy-img { margin-left: 0.45em; }
    #|.chord-play svg, .chord-copy-img svg { vertical-align: -0.3em; }
    #|.chord-copy-img:hover, .chord-play:hover { opacity: 1; }
    #|.chord-cheatsheet { display: grid; font-size: 0.78em; grid-template-columns: max-content 1fr; column-gap: 1.1em; row-gap: 0.28em; align-items: baseline; }
    #|.chord-cheatsheet code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.95em; white-space: nowrap; }
    #|.chord-cheatsheet span { opacity: 0.85; }
    #|.chord-cheat-head { grid-column: 1 / -1; font-weight: 700; font-size: 0.92em; opacity: 0.75; margin-top: 0.3em; }
    #|.chord-cheat-head:first-child { margin-top: 0; }
    #|.chord-cheat-example { grid-column: 1 / -1; margin: 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.95em; border: 1px solid #8886; border-radius: 6px; padding: 0.5em 0.8em; background: #8881; user-select: all; }
    #|.chord-cell--playing { background: #8888883d; border-radius: 5px; }
    #|.chord-mod--playing { background: #8888883d; opacity: 1; } /* 再生カーソルが転調をまたいだ瞬間の点灯(ランタイムが付与) */
    #|.chord-prevkey { font-size: 0.6em; font-weight: 500; opacity: 0.45; margin-left: 0.3em; letter-spacing: 0; } /* 転調直後の小節に添える転調前ディグリー(=V) */
    #|.chord-widget[data-chord-active="degree"] .chord-panel--notes { display: none; }
    #|.chord-widget[data-chord-active="notes"] .chord-panel--degree { display: none; }
    #|.chord-widget[data-chord-active="degree"] .chord-key-select { visibility: hidden; }
    #|@media print { .chord-tabs { display: none; } }
  )
}

///|
/// ボタンアイコンの SVG 外枠(lucide 形式。stroke は currentColor でテーマ追従。
/// data-icon はクライアントランタイムの表示切替・テストの目印)
fn icon_svg(name : String, body : String) -> String {
  "<svg viewBox=\"0 0 24 24\" width=\"1.2em\" height=\"1.2em\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\" data-icon=\"" +
  name +
  "\">" +
  body +
  "</svg>"
}

///|
/// 再生ボタンのアイコン(lucide: play)
let play_icon_svg : String = icon_svg(
  "play", "<polygon points=\"6 3 20 12 6 21 6 3\"/>",
)

///|
/// 画像コピーボタンのアイコン(lucide: camera)
let camera_icon_svg : String = icon_svg(
  "camera", "<path d=\"M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z\"/><circle cx=\"12\" cy=\"13\" r=\"3\"/>",
)

///|
/// 記法チートシートの HTML（`.chord-cheatsheet`）を返す。
/// 埋め込み場所は呼び出し側が決める（フォークのプレイグラウンドでは
/// エディタのヘッダから開くモーダルに表示する）。スタイルは chord_css() に含まれる。
/// 記法の変更時は docs/chord.md と合わせて必ず更新すること。
pub fn chord_cheatsheet_html() -> String {
  (
    #|<div class="chord-cheatsheet">
    #|<div class="chord-cheat-head">コード（Key 基準のディグリーで書く）</div>
    #|<code>1</code><span>ディグリー 1〜7（Key: C なら 1=C, 6m=Am）</span>
    #|<code>#4 s4 b7</code><span>シャープ（# / s どちらでも）・フラット</span>
    #|<code>2m 4dim 5aug</code><span>マイナー / ディミニッシュ / オーギュメント</span>
    #|<code>1q</code><span>4度堆積（ルート + 完全4度 + 完全4度）</span>
    #|<code>17 1M7 1maj7 16 1add9</code><span>セブンス・シックス・add（M7 と maj7 は同じ）</span>
    #|<code>1M7(b9,#11)</code><span>テンションは括弧内にカンマ区切り</span>
    #|<code>2m7-5</code><span>ハーフディミニッシュ（m7 の直後のみ。2m7b5 / 2m7(b5) と同じ）</span>
    #|<code>1sus4 4M7(b5)</code><span>sus2/4/6・フラットファイブ</span>
    #|<code>3m/5</code><span>スラッシュベース</span>
    #|<code>b3@red</code><span>強調色（red / blue / green、末尾）</span>
    #|<div class="chord-cheat-head">スロット</div>
    #|<code>|</code><span>小節線</span>
    #|<code>%</code><span>直前のコードを繰り返す</span>
    #|<code>_</code><span>空拍（コードを伸ばす・歌詞だけ置く）</span>
    #|<code>NC</code><span>無音（N.C. も可）</span>
    #|<code>2-5 5-_-5-6</code><span>グループ: 1 スロットを等分割で分け合う（_ = 空きパート。直前の響きを伸ばす）</span>
    #|<div class="chord-cheat-head">構成</div>
    #|<code>[Aメロ]</code><span>セクションラベル（単独行）</span>
    #|<code>[key: +1] [key: F]</code><span>転調（単独行でもコード行の途中でも）。相対 ±半音 / 絶対キー名。次に書いたコードから効く（% はまたがない）</span>
    #|<code>&gt; ひかりの _ _-さきへ</code><span>直前のコード行への歌詞。空白 = 区切り、_ 単独 = 歌詞なし、断片中の _ = スペース、- = 拍分割（_-さきへ で後半から）</span>
    #|<code>key: Eb / bpm: 96 / time: 6/8</code><span>フロントマター（先頭に --- で囲んで書く。省略時 C・120・4/4）</span>
    #|<code>:2m7:</code><span>インラインコード譜（::: の外の本文中に 1 コード。ディグリー表示のみ）</span>
    #|<div class="chord-cheat-head">例: 2-5-1（コピーして試してみてください）</div>
    #|<pre class="chord-cheat-example">:::
    #|---
    #|key: C
    #|---
    #|| 2m7 5(9) | 1M7 % |
    #|:::</pre>
    #|<div class="chord-cheat-head">例: 転調と拍分割（Bメロで全音上げ）</div>
    #|<pre class="chord-cheat-example">:::
    #|---
    #|key: C
    #|---
    #|[Bメロ]
    #|| 6m7 4M7 5-_-5-6 |
    #|&gt; _-そらに むかう _-よう
    #|[key: +2]
    #|| 6m7 4M7 | 1M7 % |
    #|:::</pre>
    #|</div>
  )
}
