defmodule AntPressWeb.EditorImageControllerTest do
  use AntPressWeb.ConnCase

  import AntPress.MediaFixtures

  alias AntPress.Media

  setup :register_and_log_in_user

  defp upload(content, filename \\ "logo.png", content_type \\ "image/png") do
    path = Path.join(System.tmp_dir!(), "editor-upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  describe "POST /client/editor/images" do
    test "画像を保存して URL を返す", %{conn: conn, scope: scope} do
      conn = post(conn, ~p"/client/editor/images", %{"file" => upload(png(800, 600))})

      assert %{"url" => url, "altText" => alt} = json_response(conn, 200)
      assert [image] = Media.list_images(scope)
      assert url == Media.public_url(image)

      # alt 未設定ならファイル名を返す（本文に alt 空で挿入されるのを避ける）
      assert alt == "logo.png"
      assert {image.width, image.height} == {800, 600}
    end

    test "⚠️ 形式はブラウザ申告ではなく中身で判定する", %{conn: conn, scope: scope} do
      # content_type は image/png と申告しているが中身は HTML
      file = upload("<script>alert(1)</script>", "evil.png", "image/png")
      conn = post(conn, ~p"/client/editor/images", %{"file" => file})

      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "対応していない画像形式です"
      assert Media.list_images(scope) == []
    end

    test "SVG は拒否する", %{conn: conn} do
      file = upload(svg(), "icon.svg", "image/svg+xml")
      conn = post(conn, ~p"/client/editor/images", %{"file" => file})

      assert json_response(conn, 422)["error"] =~ "対応していない画像形式です"
    end

    test "上限を超えるファイルは拒否する", %{conn: conn, scope: scope} do
      big = png() <> :binary.copy(<<0>>, AntPress.Media.Image.max_byte_size())
      conn = post(conn, ~p"/client/editor/images", %{"file" => upload(big, "big.png")})

      assert json_response(conn, 422)["error"] =~ "上限"
      assert Media.list_images(scope) == []
    end

    test "ファイルが無ければ 400", %{conn: conn} do
      conn = post(conn, ~p"/client/editor/images", %{})

      assert json_response(conn, 400)["error"] =~ "ファイルが送信されていません"
    end

    test "ストレージが落ちていたら 502", %{conn: conn, scope: scope} do
      original = Application.fetch_env!(:antpress, :storage)

      conn =
        try do
          Application.put_env(
            :antpress,
            :storage,
            Keyword.put(original, :adapter, AntPress.Storage.FailingStub)
          )

          post(conn, ~p"/client/editor/images", %{"file" => upload(png())})
        after
          Application.put_env(:antpress, :storage, original)
        end

      assert json_response(conn, 502)["error"] =~ "保存先への書き込みに失敗しました"
      assert Media.list_images(scope) == []
    end
  end

  describe "認可" do
    test "⚠️ ログインしていないと保存できない" do
      conn = post(build_conn(), ~p"/client/editor/images", %{"file" => upload(png())})

      assert redirected_to(conn) == ~p"/client/log-in"
    end

    test "⚠️ 保存先は自分のクライアント配下になる", %{conn: conn, scope: scope} do
      # リクエストに client_id を含める余地がない設計。
      # スコープはセッションから決まる
      post(conn, ~p"/client/editor/images", %{"file" => upload(png())})

      assert [image] = Media.list_images(scope)
      assert String.starts_with?(image.storage_path, "clients/#{scope.client.id}/")
    end
  end
end
