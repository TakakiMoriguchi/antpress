defmodule AntPress.Blog.Markdown do
  @moduledoc """
  記事本文（Markdown）を配信用の HTML にレンダリングする。

  結果は `blog_articles.body_html` に保存する。配信 API が HTML を返せば
  **HP 側に Markdown パーサが不要**になる（→ `docs/DATA-MODEL.md` 3.8）。

  ## ⚠️ earmark は使わない

  廃止済みで、しかも stored XSS の CVE がある（`EEF-CVE-2026-48591`
  = 属性値のエスケープ漏れ）。廃止メッセージ自身が MDEx への移行を案内している。
  MDEx は comrak（Rust）の薄いラッパで、`rustler_precompiled` により
  ビルド時に Rust ツールチェーンを要求しない。

  ## 生 HTML は通さない（`unsafe: false`）

  Markdown に直接書いた HTML は `<!-- raw HTML omitted -->` に置き換わる。

  - **サニタイザの許可リストの正しさに依存しない。** 構造的に通らない
  - antpress の設計思想（固定スキーマ・自由な作り込みを提供しない）と一致する
  - 記事本文は client の `users`（オーナー / スタッフ）が書く。乗っ取られた
    アカウントから公開サイトへスクリプトを注入されることを防ぐ

  ⚠️ **代償**: YouTube や Google Maps の iframe 埋め込みができない。
  必要になった時点で「許可リスト付きサニタイズ」へ切り替える判断をする。
  先回りして緩めない。

  ## 拡張構文を有効にしている理由

  CommonMark の既定では**表が素のテキストになる。** Toast UI Editor の
  ツールバーには表・打ち消し線・チェックリストのボタンがあるので、
  ユーザーが作れるものが崩れないよう対応する拡張を合わせてある。

  改行は CommonMark のまま（`hardbreaks` は有効にしない）。Toast UI の
  プレビューも CommonMark 準拠なので、**エディタでの見え方と配信結果を
  一致させる**方を優先する。
  """

  # ⚠️ ここを変えると既存記事の body_html が古いままになる。
  # body_html はキャッシュなので陳腐化する（→ docs/DATA-MODEL.md 5.4）
  @options [
    extension: [
      # Toast UI のツールバーにボタンがあるもの
      table: true,
      strikethrough: true,
      tasklist: true,
      autolink: true
    ],
    render: [
      # 生 HTML を通さない（→ モジュールの説明）
      unsafe: false
    ]
  ]

  @doc """
  Markdown を HTML に変換する。

  `nil` と空文字は `""` を返す（本文が未入力の下書きがありうる）。

      iex> AntPress.Blog.Markdown.to_html("**太字**")
      "<p><strong>太字</strong></p>"
  """
  def to_html(nil), do: ""
  def to_html(""), do: ""

  def to_html(markdown) when is_binary(markdown) do
    case MDEx.to_html(markdown, @options) do
      {:ok, html} ->
        html

      {:error, reason} ->
        # レンダリングの失敗で保存自体を失敗させない。
        # 本文が空の記事として保存され、書き直せる方がよい
        require Logger
        Logger.error("Markdown のレンダリングに失敗しました reason=#{inspect(reason)}")
        ""
    end
  end

  @doc "レンダリング設定。テストと一括再生成で参照する"
  def options, do: @options
end
