defmodule AntPressWeb.ImageLiveTest do
  use AntPressWeb.ConnCase

  import Phoenix.LiveViewTest
  import AntPress.MediaFixtures
  import AntPress.AccountsFixtures

  alias AntPress.Accounts.Scope
  alias AntPress.Media

  setup :register_and_log_in_user

  defp upload(lv, name, content) do
    lv
    |> file_input("#image-upload", :images, [%{name: name, content: content}])
    |> render_upload(name)
  end

  describe "認可" do
    test "ログインしていないとログイン画面へ飛ばされる" do
      assert {:error, {:redirect, %{to: "/client/log-in"}}} =
               live(build_conn(), ~p"/client/images")
    end
  end

  describe "一覧" do
    test "画像がなければ案内を出す", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/images")

      assert html =~ "画像"
      assert html =~ "まだ画像がありません"
      assert html =~ "クリックして選択、またはここにドラッグ＆ドロップ"
    end

    test "アップロード済みの画像を表示する", %{conn: conn, scope: scope} do
      image = image_fixture(scope, %{filename: "gaikan.png", body: png(1200, 630)})

      {:ok, _lv, html} = live(conn, ~p"/client/images")

      assert html =~ "gaikan.png"
      assert html =~ Media.public_url(image)
      # 縦横サイズとファイルサイズを出す
      assert html =~ "1200×630"
      refute html =~ "まだ画像がありません"
    end

    test "代替テキストを img の alt に出す", %{conn: conn, scope: scope} do
      image_fixture(scope, %{filename: "a.png"})
      image = List.first(Media.list_images(scope))
      {:ok, _} = Media.update_image(scope, image, %{alt_text: "店舗の外観"})

      {:ok, _lv, html} = live(conn, ~p"/client/images")

      assert html =~ ~s(alt="店舗の外観")
    end

    test "⚠️ 他クライアントの画像は表示されない", %{conn: conn, scope: scope} do
      image_fixture(scope, %{filename: "mine.png"})
      image_fixture(Scope.for_user(user_fixture()), %{filename: "theirs.png"})

      {:ok, _lv, html} = live(conn, ~p"/client/images")

      assert html =~ "mine.png"
      refute html =~ "theirs.png"
    end
  end

  describe "アップロード" do
    test "選んだ時点でアップロードされ、一覧に出る", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/images")

      upload(lv, "logo.png", png(640, 480))

      assert [image] = Media.list_images(scope)
      assert image.filename == "logo.png"
      assert image.content_type == "image/png"
      assert {image.width, image.height} == {640, 480}

      assert render(lv) =~ "logo.png"
    end

    test "JPEG も上げられる", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/images")

      upload(lv, "photo.jpg", jpeg(800, 600))

      assert [image] = Media.list_images(scope)
      assert image.content_type == "image/jpeg"
    end

    test "⚠️ 拡張子を偽装したファイルは中身で弾く", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/images")

      # 「.png」という名前の HTML。accept は通るが Probe が判別できない
      html = upload(lv, "evil.png", "<script>alert(1)</script>")

      assert html =~ "対応していない画像形式です"
      assert Media.list_images(scope) == []
    end

    test "対応していない拡張子は accept で弾く", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/images")

      # accept による拒否はブラウザ側で完結し、サーバーには届かない
      assert {:error, [[_ref, :not_accepted]]} = upload(lv, "icon.svg", svg())
      assert AntPress.Media.list_images(scope) == []
    end

    test "上限を超えるファイルは弾く", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/images")
      big = png() <> :binary.copy(<<0>>, AntPress.Media.Image.max_byte_size())

      assert {:error, [[_ref, :too_large]]} = upload(lv, "big.png", big)
      assert AntPress.Media.list_images(scope) == []
    end

    test "アップロードのエラーは日本語で表示する" do
      # 上の 2 件はサーバーに届かないため、画面に出す文言は個別に確かめる。
      # 英語の atom がそのままユーザーに見えると意味が伝わらない
      alias AntPressWeb.ImageLive.Index

      assert Index.upload_error_message(:too_large) =~ "上限"
      assert Index.upload_error_message(:not_accepted) =~ "対応していない画像形式です"
      assert Index.upload_error_message(:too_many_files) =~ "10 件まで"
      assert Index.upload_error_message(:something_new) =~ "アップロードに失敗しました"
    end

    test "ストレージが落ちていたらエラーを出す", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/images")

      original = Application.fetch_env!(:antpress, :storage)

      try do
        Application.put_env(
          :antpress,
          :storage,
          Keyword.put(original, :adapter, AntPress.Storage.FailingStub)
        )

        assert upload(lv, "logo.png", png()) =~ "保存先への書き込みに失敗しました"
      after
        Application.put_env(:antpress, :storage, original)
      end

      assert Media.list_images(scope) == []
    end
  end

  describe "代替テキストの設定" do
    test "保存できる", %{conn: conn, scope: scope} do
      image = image_fixture(scope, %{filename: "gaikan.png"})

      {:ok, lv, _html} = live(conn, ~p"/client/images")

      html =
        lv
        |> element("form[phx-submit='save-alt']")
        |> render_submit(%{"image_id" => image.id, "alt_text" => "店舗の外観"})

      assert html =~ "代替テキストを保存しました"
      assert Media.get_image!(scope, image.id).alt_text == "店舗の外観"
    end

    test "長すぎるとエラーを出す", %{conn: conn, scope: scope} do
      image = image_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/client/images")

      html =
        lv
        |> element("form[phx-submit='save-alt']")
        |> render_submit(%{"image_id" => image.id, "alt_text" => String.duplicate("あ", 201)})

      assert html =~ "200"
      assert Media.get_image!(scope, image.id).alt_text == nil
    end

    test "⚠️ 他クライアントの画像は更新できない", %{conn: conn, scope: scope} do
      Process.flag(:trap_exit, true)
      image_fixture(scope)
      other = image_fixture(Scope.for_user(user_fixture()))

      {:ok, lv, _html} = live(conn, ~p"/client/images")

      # スコープ外の id を送ると get_image!/2 が落ちる。
      # 更新されるより落ちる方が安全なので、これが期待動作
      assert catch_exit(
               lv
               |> element("form[phx-submit='save-alt']")
               |> render_submit(%{"image_id" => other.id, "alt_text" => "乗っ取り"})
             )

      assert AntPress.Repo.get!(AntPress.Media.Image, other.id).alt_text == nil
    end
  end

  describe "削除" do
    test "一覧から消える", %{conn: conn, scope: scope} do
      image = image_fixture(scope, %{filename: "gaikan.png"})

      {:ok, lv, html} = live(conn, ~p"/client/images")
      assert html =~ "gaikan.png"

      html = render_click(lv, "delete", %{"id" => image.id})

      refute html =~ "gaikan.png"
      assert html =~ "画像を削除しました"
      assert Media.list_images(scope) == []
    end

    test "全部消すと案内が戻る", %{conn: conn, scope: scope} do
      image = image_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/client/images")
      html = render_click(lv, "delete", %{"id" => image.id})

      assert html =~ "まだ画像がありません"
    end

    test "⚠️ 他クライアントの画像は削除できない", %{conn: conn, scope: scope} do
      Process.flag(:trap_exit, true)
      image_fixture(scope)
      other = image_fixture(Scope.for_user(user_fixture()))

      {:ok, lv, _html} = live(conn, ~p"/client/images")

      assert catch_exit(render_click(lv, "delete", %{"id" => other.id}))

      assert AntPress.Repo.get!(AntPress.Media.Image, other.id)
    end
  end

  describe "ナビゲーション" do
    test "クライアント側のメニューに「画像」が出る", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/categories")

      assert html =~ ~s(href="/client/images")
    end
  end
end
