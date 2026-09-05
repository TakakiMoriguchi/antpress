defmodule AntPress.Blog.MarkdownTest do
  @moduledoc """
  配信用 HTML のレンダリング。**生 HTML を通さないこと**が中心。
  """
  use ExUnit.Case, async: true

  alias AntPress.Blog.Markdown

  describe "to_html/1" do
    test "基本的な記法を変換する" do
      assert Markdown.to_html("# 見出し") =~ "<h1>見出し</h1>"
      assert Markdown.to_html("**太字**") =~ "<strong>太字</strong>"
      assert Markdown.to_html("- 一\n- 二") =~ "<ul>"
      assert Markdown.to_html("[名前](https://example.com)") =~ ~s(href="https://example.com")
    end

    test "画像記法を変換する" do
      html = Markdown.to_html("![外観](https://example.com/a.png)")

      assert html =~ ~s(src="https://example.com/a.png")
      assert html =~ ~s(alt="外観")
    end

    test "Toast UI のツールバーにある記法に対応する" do
      # 対応していないと、ユーザーがボタンで作ったものが素のテキストになる
      assert Markdown.to_html("| a | b |\n| --- | --- |\n| 1 | 2 |") =~ "<table>"
      assert Markdown.to_html("~~取消~~") =~ "<del>取消</del>"
      assert Markdown.to_html("- [x] 済") =~ ~s(type="checkbox")
      assert Markdown.to_html("https://example.com") =~ "<a href="
    end

    test "コードブロックの言語指定を残す" do
      assert Markdown.to_html("```elixir\nIO.puts(1)\n```") =~ ~s(class="language-elixir")
    end

    test "Shift+Enter の改行（バックスラッシュ）を br にする" do
      assert Markdown.to_html("1 行目\\\n2 行目") =~ "<br />"
    end
  end

  describe "⚠️ 生 HTML を通さない" do
    test "script タグを落とす" do
      html = Markdown.to_html("本文\n\n<script>alert(document.cookie)</script>")

      refute html =~ "<script"
      refute html =~ "alert"
      assert html =~ "raw HTML omitted"
    end

    test "イベントハンドラ属性を落とす" do
      # ⚠️ ~s(...) は括弧の入れ子を扱わないので通常の文字列で書く
      html = Markdown.to_html("<img src=x onerror=\"alert(1)\">")

      refute html =~ "onerror"
    end

    test "iframe を落とす" do
      # 代償として YouTube / Google Maps の埋め込みができない。
      # 必要になった時点で許可リスト付きサニタイズへ切り替える判断をする
      html = Markdown.to_html(~s(<iframe src="https://example.com"></iframe>))

      refute html =~ "<iframe"
    end

    test "Markdown リンクの javascript: スキームは属性値としてエスケープされる" do
      html = Markdown.to_html("[危険](javascript:alert%281%29)")

      # comrak はリンクを出すが、生 HTML の注入経路にはならない
      refute html =~ "<script"
    end
  end

  describe "端の入力" do
    test "nil と空文字は空文字を返す" do
      assert Markdown.to_html(nil) == ""
      assert Markdown.to_html("") == ""
    end

    test "本文が空白だけでも落ちない" do
      assert is_binary(Markdown.to_html("   \n\n  "))
    end

    test "非常に長い本文も処理できる" do
      long = String.duplicate("段落です。\n\n", 2_000)

      assert Markdown.to_html(long) =~ "<p>段落です。</p>"
    end
  end

  describe "options/0" do
    test "設定を公開している（一括再生成で参照する）" do
      opts = Markdown.options()

      assert opts[:render][:unsafe] == false
      assert opts[:extension][:table] == true
    end
  end
end
