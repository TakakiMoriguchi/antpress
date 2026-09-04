defmodule AntPress.Repo.Migrations.AddAntpressFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # 所属するクライアント（テナント）。
      # クライアント側のユーザーは必ず 1 つのクライアントに属する。
      # クライアントを削除すればユーザーも消える（→ docs/DECISIONS.md 3.5）
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false

      # オーナーは developer が発行し、スタッフはオーナーが発行する
      # （→ docs/DECISIONS.md 3.5）
      add :role, :string, null: false, default: "staff"

      # 表示名。作成は developer / オーナーのみなので NOT NULL で問題ない
      add :name, :string, null: false
    end

    create constraint(:users, :users_role_valid, check: "role IN ('owner', 'staff')")

    # クライアント配下のユーザー一覧（主クエリ）
    create index(:users, [:client_id])
  end
end
