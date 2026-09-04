defmodule AntPress.Storage.SupabaseTest do
  @moduledoc """
  Supabase Storage アダプタのテスト。

  実際の Supabase には到達しない。`Req.Test` をプラグとして差し込み、
  **送っているリクエストの形**を検証する。

  こうしている理由は 2 つ。

  1. テストを認証情報とネットワークに依存させない
  2. 認証情報が用意できる前にアダプタを完成させられる
  """
  use ExUnit.Case

  import AntPress.MediaFixtures

  alias AntPress.Storage
  alias AntPress.Storage.Supabase

  @url "https://exampleproject.supabase.co"
  @key "service-role-key-do-not-log"
  @path "clients/11111111-1111-1111-1111-111111111111/22222222.png"

  setup do
    original = Application.fetch_env!(:antpress, :storage)

    Application.put_env(:antpress, :storage,
      adapter: Supabase,
      url: @url,
      service_role_key: @key,
      bucket: "images",
      plug: {Req.Test, __MODULE__}
    )

    on_exit(fn -> Application.put_env(:antpress, :storage, original) end)
    :ok
  end

  describe "put/3" do
    test "バケットのオブジェクトパスへ POST する" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.host == "exampleproject.supabase.co"
        assert conn.request_path == "/storage/v1/object/images/#{@path}"

        Plug.Conn.send_resp(conn, 200, ~s({"Key":"images/#{@path}"}))
      end)

      assert Storage.put(@path, png(), "image/png") == :ok
    end

    test "Bearer 認証と content-type を送る" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer #{@key}"]
        assert Plug.Conn.get_req_header(conn, "content-type") == ["image/png"]
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      assert Storage.put(@path, png(), "image/png") == :ok
    end

    test "x-upsert を付ける（同じパスは上書きする契約）" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-upsert") == ["true"]
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      assert Storage.put(@path, png(), "image/png") == :ok
    end

    test "バイナリをそのまま送る" do
      body = png(1200, 630)

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, received, conn} = Plug.Conn.read_body(conn)
        assert received == body
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      assert Storage.put(@path, body, "image/png") == :ok
    end

    test "2xx 以外はエラーを返す" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 403, ~s({"message":"new row violates row-level security"}))
      end)

      assert {:error, {:supabase_storage, 403, body}} = Storage.put(@path, png(), "image/png")
      assert body =~ "row-level security"
    end

    test "⚠️ エラーに service_role_key を含めない" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 500, "internal error")
      end)

      assert {:error, error} = Storage.put(@path, png(), "image/png")

      # 漏れると developer 以外がバケットを操作できるようになる
      refute inspect(error) =~ @key
    end

    test "通信自体が失敗した場合もエラーを返す" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:supabase_storage, _}} = Storage.put(@path, png(), "image/png")
    end
  end

  describe "delete/1" do
    test "オブジェクトパスへ DELETE する" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/storage/v1/object/images/#{@path}"
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      assert Storage.delete(@path) == :ok
    end

    test "存在しないオブジェクトは 404 が返るのでエラーになる" do
      # ローカルアダプタと違って冪等にはならない。
      # Media 側は削除失敗をログに残して先に進むので実害はない
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 404, ~s({"message":"Object not found"}))
      end)

      assert {:error, {:supabase_storage, 404, _}} = Storage.delete(@path)
    end
  end

  describe "public_url/1" do
    test "public バケット用の URL を組む" do
      # HP の <img src> から読まれるので、認証なしで取得できる必要がある
      assert Storage.public_url(@path) ==
               "#{@url}/storage/v1/object/public/images/#{@path}"
    end

    test "バケット名を設定していなければ既定の antpress を使う" do
      # ⚠️ 環境変数名は SUPABASE_STORAGE_BUCKET、既定は antpress。
      # .env.example と runtime.exs で食い違うと 404 になるので固定する
      config = Application.fetch_env!(:antpress, :storage)
      Application.put_env(:antpress, :storage, Keyword.delete(config, :bucket))

      assert Storage.public_url(@path) =~ "/object/public/antpress/"
    end

    test "バケット名は設定から読む" do
      config = Application.fetch_env!(:antpress, :storage)
      Application.put_env(:antpress, :storage, Keyword.put(config, :bucket, "assets"))

      assert Storage.public_url(@path) =~ "/object/public/assets/"
    end

    test "url の末尾スラッシュを二重にしない" do
      config = Application.fetch_env!(:antpress, :storage)
      Application.put_env(:antpress, :storage, Keyword.put(config, :url, @url <> "/"))

      refute Storage.public_url(@path) =~ "supabase.co//"
    end
  end

  describe "パスの検証" do
    test "ディレクトリトラバーサルを拒否する" do
      # パスは antpress が生成するので通常ここは通らないが、
      # ストレージへの書き込みは影響が大きいので二重に防ぐ
      assert Storage.put("../../etc/passwd", png(), "image/png") == {:error, :invalid_path}
      assert Storage.delete("clients/../../secret") == {:error, :invalid_path}
      assert Storage.put("/absolute/path.png", png(), "image/png") == {:error, :invalid_path}
      assert Storage.put("", png(), "image/png") == {:error, :invalid_path}
    end
  end
end
