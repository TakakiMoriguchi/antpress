defmodule AntPress.Repo.Migrations.CreateDevelopersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:developers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:developers, [:email])

    create table(:developers_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :developer_id, references(:developers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:developers_tokens, [:developer_id])
    create unique_index(:developers_tokens, [:context, :token])
  end
end
