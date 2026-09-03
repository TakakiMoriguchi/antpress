defmodule AntPress.Repo.Migrations.AddAntpressFieldsToDevelopers do
  use Ecto.Migration

  def change do
    alter table(:developers) do
      # admin / developer の区別。admin 自身も developer レコードを 1 件持つ
      # （→ docs/DECISIONS.md 1.3）
      add :role, :string, null: false, default: "developer"

      # 屋号・氏名。作成は admin または seed のみなので NOT NULL で問題ない
      add :name, :string, null: false

      # ⚠️ 暗号化して保存する（ハッシュではない）。Claude API を叩くのに平文が必要。
      #    → AntPress.Encrypted.Binary / docs/DECISIONS.md 3.1
      add :anthropic_api_key, :binary

      # admin の手動操作。これが実質の課金コントロール。
      # suspended で管理画面ログインと配信 API の両方を止める（→ docs/DECISIONS.md 3.10）
      add :status, :string, null: false, default: "active"

      # admin 専用メモ（契約日・年額・入金状況などの自由記述）
      add :note, :text
    end

    # Ecto.Enum はアプリ層の検証なので、DB 側にも制約を張る
    create constraint(:developers, :developers_role_valid,
             check: "role IN ('admin', 'developer')"
           )

    create constraint(:developers, :developers_status_valid,
             check: "status IN ('active', 'suspended')"
           )

    # 配信 API が停止判定で参照する
    create index(:developers, [:status])
  end
end
