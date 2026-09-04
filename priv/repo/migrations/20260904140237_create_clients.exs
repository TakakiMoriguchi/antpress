defmodule AntPress.Repo.Migrations.CreateClients do
  use Ecto.Migration

  def change do
    create table(:clients, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # 契約している developer。admin 直契約は admin 自身の developer レコードを
      # 指すため NOT NULL で成立する（→ docs/DECISIONS.md 1.3）
      add :developer_id, references(:developers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false

      # 運営者向けの識別子。グローバル一意（クライアント単位ではない）
      add :slug, :string, null: false

      # 課金額には影響しない機能フラグ（→ docs/DECISIONS.md 3.1）
      add :plan, :string, null: false

      # お問い合わせの転送先（→ docs/DECISIONS.md 3.4）
      add :contact_notification_email, :string

      # 記事公開時に POST する Deploy Hook URL（→ docs/DECISIONS.md 3.6）
      add :webhook_url, :string

      # suspended で管理画面ログインと配信 API の両方を止める
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    # Ecto.Enum はアプリ層の検証なので DB 側にも制約を張る
    create constraint(:clients, :clients_plan_valid, check: "plan IN ('basic', 'ai')")

    create constraint(:clients, :clients_status_valid, check: "status IN ('active', 'suspended')")

    # developer のクライアント一覧（主クエリ）
    create index(:clients, [:developer_id])

    # 配信 API が停止判定で参照する
    create index(:clients, [:status])

    create unique_index(:clients, [:slug])
  end
end
