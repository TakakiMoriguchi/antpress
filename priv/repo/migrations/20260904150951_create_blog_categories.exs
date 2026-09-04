defmodule AntPress.Repo.Migrations.CreateBlogCategories do
  use Ecto.Migration

  def change do
    create table(:blog_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false

      # 記事 URL に使う。スラッグの一意性はクライアント単位
      # （複数クライアントが同じ slug を持てる → docs/DATA-MODEL.md 1.3）
      add :slug, :string, null: false

      # 表示順。クライアントが並び替えできる
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # クライアント配下の一覧（主クエリ）。表示順で並べる
    create index(:blog_categories, [:client_id, :position])

    create unique_index(:blog_categories, [:client_id, :slug])
  end
end
