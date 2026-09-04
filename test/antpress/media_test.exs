defmodule AntPress.MediaTest do
  use AntPress.DataCase

  import AntPress.AccountsFixtures
  import AntPress.MediaFixtures

  alias AntPress.Media
  alias AntPress.Media.Image
  alias AntPress.Accounts.Scope

  setup do
    user = user_fixture()
    %{scope: Scope.for_user(user), user: user}
  end

  # ローカルアダプタが実際に書いたファイルの絶対パス
  defp stored_file(%Image{storage_path: path}) do
    Path.join(Keyword.fetch!(AntPress.Storage.config(), :root), path)
  end

  describe "create_image/2" do
    test "画像を保存し、メタデータを記録する", %{scope: scope} do
      assert {:ok, %Image{} = image} =
               Media.create_image(scope, %{filename: "logo.png", body: png(1200, 630)})

      assert image.client_id == scope.client.id
      assert image.filename == "logo.png"
      assert image.content_type == "image/png"
      assert image.width == 1200
      assert image.height == 630
      assert image.byte_size == byte_size(png(1200, 630))
    end

    test "ファイル本体をストレージに書く", %{scope: scope} do
      image = image_fixture(scope, %{body: png()})

      assert File.exists?(stored_file(image))
      assert File.read!(stored_file(image)) == png()
    end

    test "storage_path は clients/{client_id}/ 配下になる", %{scope: scope} do
      image = image_fixture(scope)

      # テナント分離（→ docs/DATA-MODEL.md 3.9）
      assert String.starts_with?(image.storage_path, "clients/#{scope.client.id}/")
      assert String.ends_with?(image.storage_path, ".png")
    end

    test "⚠️ content_type はファイル名ではなく中身から決まる", %{scope: scope} do
      # 「.jpg」という名前だが中身は PNG
      assert {:ok, image} =
               Media.create_image(scope, %{filename: "photo.jpg", body: png()})

      assert image.content_type == "image/png"
      assert String.ends_with?(image.storage_path, ".png")
      # 元のファイル名は表示用に残す
      assert image.filename == "photo.jpg"
    end

    test "JPEG / GIF / WebP も保存できる", %{scope: scope} do
      assert {:ok, j} = Media.create_image(scope, %{filename: "a.jpg", body: jpeg(640, 480)})
      assert {:ok, g} = Media.create_image(scope, %{filename: "b.gif", body: gif(320, 240)})
      assert {:ok, w} = Media.create_image(scope, %{filename: "c.webp", body: webp(200, 100)})

      assert {j.content_type, j.width, j.height} == {"image/jpeg", 640, 480}
      assert {g.content_type, g.width, g.height} == {"image/gif", 320, 240}
      assert {w.content_type, w.width, w.height} == {"image/webp", 200, 100}
    end

    test "対応していない形式は拒否する", %{scope: scope} do
      assert {:error, :unsupported_format} =
               Media.create_image(scope, %{filename: "x.png", body: not_an_image()})
    end

    test "SVG は拒否する（スクリプトを埋め込めるため）", %{scope: scope} do
      assert {:error, :unsupported_format} =
               Media.create_image(scope, %{filename: "icon.svg", body: svg()})
    end

    test "上限を超えるファイルは拒否し、**ストレージには書かない**", %{scope: scope} do
      big = png() <> :binary.copy(<<0>>, Image.max_byte_size())

      assert {:error, %Ecto.Changeset{} = changeset} =
               Media.create_image(scope, %{filename: "big.png", body: big})

      assert "ファイルサイズが上限（5MB）を超えています" in errors_on(changeset).byte_size

      # 検証はアップロードの前に行う（孤児オブジェクトを作らない）
      assert Media.list_images(scope) == []
      assert ls_client_dir(scope) == []
    end

    test "サイズが読めない画像でも保存する", %{scope: scope} do
      # PNG シグネチャはあるが IHDR が無い。形式は判別できるので保存はする
      truncated = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0, 0>>

      assert {:ok, image} = Media.create_image(scope, %{filename: "odd.png", body: truncated})
      assert image.width == nil
      assert image.height == nil
    end

    test "ストレージへの書き込みが失敗したら DB にも残さない", %{scope: scope} do
      with_storage(AntPress.Storage.FailingStub, fn ->
        assert {:error, {:storage, :stub_failure}} =
                 Media.create_image(scope, %{filename: "logo.png", body: png()})
      end)

      assert Media.list_images(scope) == []
    end

    test "DB 挿入が失敗したらストレージのオブジェクトを消す", %{scope: %Scope{} = scope} do
      # 存在しないクライアントを指すスコープを作り、FK 違反を起こす
      orphan_scope = %Scope{scope | client: %{scope.client | id: Ecto.UUID.generate()}}

      assert {:error, %Ecto.Changeset{}} =
               Media.create_image(orphan_scope, %{filename: "logo.png", body: png()})

      # 参照の無いオブジェクトを残さない（→ AntPress.Media の説明）
      assert ls_client_dir(orphan_scope) == []
    end
  end

  describe "list_images/1" do
    test "新しいものが先に並ぶ", %{scope: scope} do
      old = image_fixture(scope, %{filename: "old.png"})
      new = image_fixture(scope, %{filename: "new.png"})

      assert Enum.map(Media.list_images(scope), & &1.id) == [new.id, old.id]
    end

    test "⚠️ 他クライアントの画像は見えない", %{scope: scope} do
      mine = image_fixture(scope)
      other = image_fixture(Scope.for_user(user_fixture()))

      ids = Enum.map(Media.list_images(scope), & &1.id)
      assert mine.id in ids
      refute other.id in ids
    end
  end

  describe "get_image!/2" do
    test "自分の画像は取得できる", %{scope: scope} do
      image = image_fixture(scope)
      assert Media.get_image!(scope, image.id).id == image.id
    end

    test "⚠️ 他クライアントの画像は取得できない", %{scope: scope} do
      other = image_fixture(Scope.for_user(user_fixture()))

      assert_raise Ecto.NoResultsError, fn -> Media.get_image!(scope, other.id) end
    end
  end

  describe "update_image/3" do
    test "代替テキストを更新できる", %{scope: scope} do
      image = image_fixture(scope)

      assert {:ok, updated} = Media.update_image(scope, image, %{alt_text: "店舗の外観"})
      assert updated.alt_text == "店舗の外観"
    end

    test "⚠️ 代替テキスト以外は変更できない", %{scope: scope} do
      image = image_fixture(scope)

      {:ok, updated} =
        Media.update_image(scope, image, %{
          alt_text: "説明",
          storage_path: "clients/somewhere-else/evil.png",
          content_type: "text/html",
          byte_size: 1
        })

      assert updated.storage_path == image.storage_path
      assert updated.content_type == image.content_type
      assert updated.byte_size == image.byte_size
    end

    test "長すぎる代替テキストは拒否する", %{scope: scope} do
      image = image_fixture(scope)

      assert {:error, changeset} =
               Media.update_image(scope, image, %{alt_text: String.duplicate("あ", 201)})

      assert errors_on(changeset).alt_text != []
    end

    test "⚠️ 他クライアントの画像は更新できない", %{scope: scope} do
      other = image_fixture(Scope.for_user(user_fixture()))

      assert_raise MatchError, fn -> Media.update_image(scope, other, %{alt_text: "x"}) end
    end
  end

  describe "delete_image/2" do
    test "レコードとファイル本体の両方を消す", %{scope: scope} do
      image = image_fixture(scope)
      path = stored_file(image)
      assert File.exists?(path)

      assert {:ok, _} = Media.delete_image(scope, image)

      refute File.exists?(path)
      assert Media.list_images(scope) == []
    end

    test "本体の削除に失敗してもレコードは消える", %{scope: scope} do
      image = image_fixture(scope)

      # ストレージ側が失敗しても、ユーザーには再試行の手段がない。
      # 孤児オブジェクトを残す方に倒す（→ AntPress.Media の説明）
      with_storage(AntPress.Storage.FailingStub, fn ->
        assert {:ok, _} = Media.delete_image(scope, image)
      end)

      assert Media.list_images(scope) == []
    end

    test "⚠️ 他クライアントの画像は削除できない", %{scope: scope} do
      other = image_fixture(Scope.for_user(user_fixture()))

      assert_raise MatchError, fn -> Media.delete_image(scope, other) end

      # レコードもファイルも残っている
      assert AntPress.Repo.get!(Image, other.id)
      assert File.exists?(stored_file(other))
    end
  end

  describe "public_url/1" do
    test "ストレージのアダプタが決めた URL を返す", %{scope: scope} do
      image = image_fixture(scope)

      assert Media.public_url(image) == "/uploads/" <> image.storage_path
    end
  end

  describe "PubSub" do
    test "作成・更新・削除が通知される", %{scope: scope} do
      Media.subscribe_images(scope)

      image = image_fixture(scope)
      assert_receive {:created, %Image{id: id}} when id == image.id

      {:ok, image} = Media.update_image(scope, image, %{alt_text: "説明"})
      assert_receive {:updated, %Image{id: id}} when id == image.id

      {:ok, _} = Media.delete_image(scope, image)
      assert_receive {:deleted, %Image{id: id}} when id == image.id
    end
  end

  # ── ヘルパ ──

  defp with_storage(adapter, fun) do
    original = Application.fetch_env!(:antpress, :storage)

    try do
      Application.put_env(:antpress, :storage, Keyword.put(original, :adapter, adapter))
      fun.()
    after
      Application.put_env(:antpress, :storage, original)
    end
  end

  defp ls_client_dir(%Scope{} = scope) do
    dir =
      Keyword.fetch!(AntPress.Storage.config(), :root)
      |> Path.join("clients/#{scope.client.id}")

    case File.ls(dir) do
      {:ok, entries} -> entries
      {:error, :enoent} -> []
    end
  end
end
