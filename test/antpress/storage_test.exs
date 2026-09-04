defmodule AntPress.StorageTest do
  @moduledoc """
  ストレージ層の設定に関する不変条件。
  """
  use ExUnit.Case

  import AntPress.MediaFixtures

  alias AntPress.Storage

  describe "テスト環境の設定" do
    test "⚠️ テストは必ずローカルアダプタを使う" do
      # `SUPABASE_URL` が export されていても**本物の Supabase を叩かない**。
      # config/runtime.exs の切り替えは :dev / :prod だけを対象にしている。
      # ここが崩れると、テストがユーザーのバケットにファイルを書き始める
      assert Storage.adapter() == AntPress.Storage.Local
      refute Keyword.has_key?(Storage.config(), :url)
    end

    test "書き込み先はプロジェクト外の一時ディレクトリ" do
      # リポジトリを汚さない
      root = Storage.config!(:root)

      refute String.starts_with?(root, File.cwd!())
      assert String.contains?(root, "antpress-test-uploads")
    end
  end

  describe "Local アダプタ" do
    setup do
      path = "test/#{System.unique_integer([:positive])}.png"
      on_exit(fn -> Storage.delete(path) end)
      %{path: path}
    end

    test "保存して読み出せる", %{path: path} do
      assert Storage.put(path, png(), "image/png") == :ok
      assert File.read!(Path.join(Storage.config!(:root), path)) == png()
    end

    test "同じパスへの再書き込みは上書きする", %{path: path} do
      :ok = Storage.put(path, png(100, 100), "image/png")
      :ok = Storage.put(path, png(200, 200), "image/png")

      assert File.read!(Path.join(Storage.config!(:root), path)) == png(200, 200)
    end

    test "存在しないパスの削除も成功扱い（冪等）" do
      assert Storage.delete("test/does-not-exist.png") == :ok
    end

    test "URL は url_prefix を前置する", %{path: path} do
      assert Storage.public_url(path) == "/uploads/" <> path
    end

    test "⚠️ ディレクトリトラバーサルを拒否する" do
      assert Storage.put("../escaped.png", png(), "image/png") == {:error, :invalid_path}
      assert Storage.delete("../escaped.png") == {:error, :invalid_path}
    end
  end
end
