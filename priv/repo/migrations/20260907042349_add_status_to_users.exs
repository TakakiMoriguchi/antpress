defmodule AntPress.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def change do
    # スタッフが辞めたときにアクセスを止められるようにする。
    # クライアントを消せない方針（→ docs/DECISIONS.md 3.8）と同じ考え方で、
    # レコードを消さずに止める
    alter table(:users) do
      add :status, :string, null: false, default: "active"
    end

    # Ecto.Enum に加えて DB 側でも値を絞る
    create constraint(:users, :users_status_must_be_valid,
             check: "status IN ('active', 'suspended')"
           )
  end
end
