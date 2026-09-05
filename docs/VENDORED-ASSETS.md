# 同梱している外部アセット

`priv/static/vendor/` に置いたファイルの出所と更新手順。

⚠️ **このメモを `priv/static/` の中に置かないこと。**
`AntPressWeb.static_paths/0` に `vendor` を入れているため、
その配下のファイルは**すべて公開配信される**（実際に README が
HTTP 200 で取得できる状態になっていた）。

---

## Toast UI Editor

| 項目 | 値 |
| --- | --- |
| バージョン | **3.2.2** |
| ライセンス | **MIT** |
| 提供元 | NHN Cloud FE Development Lab |
| 取得元 | `https://uicdn.toast.com/editor/3.2.2/` |
| 取得日 | 2026-09-05 |

## なぜ npm ではなく同梱なのか

antpress は `package.json` を持たない。JS は `assets/vendor/` に置く方式
（`topbar.js` / `heroicons.js` と同じ）。npm を入れるとデプロイイメージに
Node が必要になり、moving parts が増える。

## ⚠️ npm の `dist/toastui-editor.js` は使えない

npm パッケージの dist は **prosemirror を同梱していない**（`dependencies`
として外部化されている）。`<script>` タグで読むと動かず、esbuild で
バンドルしようとすると `prosemirror-state` が解決できずに失敗する。

**自己完結しているのは CDN の `toastui-editor-all.min.js` だけ。**
prosemirror-view / prosemirror-state / prosemirror-model が同梱されている
ことを文字列リテラルで確認した（`ProseMirror-hideselection` など）。
なお `-all` はプラグイン（chart / uml / syntax highlight）を含まない。

## なぜ esbuild のバンドルに入れないのか

522KB を `app.js` に入れると**全ページが読み込むことになる。**
記事フォーム（`/client/articles/new` と `/edit`）だけで使うので、
`priv/static/vendor/` に置いて `<script>` で直接読む。

そのため `AntPressWeb.static_paths/0` に `vendor` を追加している。

## ブラウザでのグローバル

UMD なので `window.toastui.Editor` に入る。

## 更新手順

```sh
V=3.2.2   # 新しいバージョンに変える
cd priv/static/vendor/toastui-editor
curl -sLO https://uicdn.toast.com/editor/$V/toastui-editor-all.min.js
curl -sLO https://uicdn.toast.com/editor/$V/toastui-editor.min.css
curl -sL -o toastui-editor-dark.min.css https://uicdn.toast.com/editor/$V/theme/toastui-editor-dark.min.css
curl -sL -o i18n-ja-jp.min.js https://uicdn.toast.com/editor/$V/i18n/ja-jp.min.js
shasum -a 256 *   # docs/VENDORED-ASSETS.md の表を更新する
```

## チェックサム（SHA-256）

再取得したものが同一か確認するために記録している。

| ファイル | サイズ | SHA-256 |
| --- | --- | --- |
| `i18n-ja-jp.min.js` | 3KB | `d18f532e5762534438d92655c5e2f7e6d424a764f0ef3aa180b199012db7fe1a` |
| `toastui-editor-all.min.js` | 522KB | `f50e1b7c0fc4e5d9a1ccd0d8be78cb3a950ccb3bf676fbf1627810c76aeaedd8` |
| `toastui-editor-dark.min.css` | 13KB | `68d4eb725ef9040c9713a4b140a2bcbfd38a8aee91f1b476bb9c2425b02ccd15` |
| `toastui-editor.min.css` | 162KB | `c70e24c68fefc205e8e504edc07fd6a5efd3044a623b4be7e3ac16cc8a736ed9` |
