defmodule AntPress.Repo.Migrations.CreateImages do
  use Ecto.Migration

  def change do
    create table(:images, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false

      # Supabase Storage 内のパス。`clients/{client_id}/{uuid}.{ext}`
      add :storage_path, :string, null: false

      # アップロード時の元ファイル名。表示にのみ使う（保存パスには使わない）
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :integer, null: false
      add :width, :integer
      add :height, :integer
      add :alt_text, :string

      # ⚠️ 他のテーブルは :utc_datetime（秒）だが、画像だけ **マイクロ秒**にする。
      #
      # 画像は 10 件まとめてアップロードできるので、**同一秒に複数行入るのが
      # 例外ではなく普通**。秒精度だと一覧の並び順が同着になり、
      # 第 2 キー（id = ランダムな UUID）で決まってしまう。
      # 「まとめて上げた画像がばらばらの順で並ぶ」という見え方になる。
      timestamps(type: :utc_datetime_usec)
    end

    # 画像一覧（→ docs/DATA-MODEL.md 4）
    create index(:images, [:client_id, "inserted_at DESC"])

    # 同じパスに 2 レコードが向くと、片方を消したときにもう片方が壊れる
    create unique_index(:images, [:storage_path])

    # Ecto.Enum に加えて DB 側でも許可する形式を絞る。
    # SVG を含めないのは、スクリプトを埋め込めて XSS になりうるため
    create constraint(:images, :images_content_type_must_be_supported_image,
             check: "content_type IN ('image/jpeg', 'image/png', 'image/gif', 'image/webp')"
           )

    create constraint(:images, :images_byte_size_must_be_positive, check: "byte_size > 0")
  end
end
