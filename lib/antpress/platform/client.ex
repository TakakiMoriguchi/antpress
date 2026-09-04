defmodule AntPress.Platform.Client do
  @moduledoc """
  クライアント（テナント）。HP のコンテンツを管理する店舗・企業。

  必ず 1 つの developer に紐づく。admin と直接契約しているクライアントは
  **admin 自身の developer レコード**を指す（→ `docs/DECISIONS.md` 1.3）。
  そのため `developer_id` は常に非 NULL で、「直接契約」の特別扱いが不要になる。
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AntPress.Platform.Developer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "clients" do
    field :name, :string

    # 運営者向けの識別子。グローバル一意
    field :slug, :string

    # 課金額には影響しない機能フラグ（→ docs/DECISIONS.md 3.1）
    field :plan, Ecto.Enum, values: [:basic, :ai]

    # お問い合わせの転送先（→ docs/DECISIONS.md 3.4）
    field :contact_notification_email, :string

    # 記事公開時に POST する Deploy Hook URL（→ docs/DECISIONS.md 3.6）
    field :webhook_url, :string

    field :status, Ecto.Enum, values: [:active, :suspended], default: :active

    belongs_to :developer, Developer

    timestamps(type: :utc_datetime)
  end

  @doc """
  クライアントの changeset。

  ⚠️ **`developer_id` は `cast` しない。** スコープから `put_change` で設定する。
  attrs から受け取ると、developer が他の developer 配下にクライアントを
  作れてしまう。
  """
  def changeset(client, attrs, developer_scope) do
    client
    |> cast(attrs, [:name, :slug, :plan, :contact_notification_email, :webhook_url, :status])
    |> validate_required([:name, :slug, :plan])
    |> validate_length(:name, max: 160)
    |> validate_slug()
    |> validate_email(:contact_notification_email)
    |> validate_webhook_url()
    |> validate_ai_plan_requires_anthropic_key(developer_scope)
    |> unique_constraint(:slug)
    |> check_constraint(:plan, name: :clients_plan_valid)
    |> check_constraint(:status, name: :clients_status_valid)
    |> put_developer_id(developer_scope)
  end

  # ⚠️ `developer_id` は**作成時のみ**設定する。
  #
  # 無条件に `put_change` すると、admin が他人のクライアントを編集したときに
  # そのクライアントが admin 配下に付け替わってしまう（実際にテストで検出した）。
  #
  # また `cast` していないので attrs からも設定できない。つまり所有者を変える
  # 経路が存在しない。クライアントの移管（→ docs/DATA-MODEL.md 3.3）が必要に
  # なったら、admin 専用の専用関数として明示的に用意する。
  defp put_developer_id(changeset, developer_scope) do
    case changeset.data.developer_id do
      nil -> put_change(changeset, :developer_id, developer_scope.developer.id)
      _existing -> changeset
    end
  end

  # スラッグは URL や識別子に使うので英小文字・数字・ハイフンのみ
  defp validate_slug(changeset) do
    changeset
    |> validate_length(:slug, min: 2, max: 63)
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "英小文字・数字・ハイフンのみ使えます（先頭と末尾はハイフン不可）"
    )
  end

  defp validate_email(changeset, field) do
    changeset
    |> validate_format(field, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "メールアドレスの形式が正しくありません")
    |> validate_length(field, max: 160)
  end

  # Deploy Hook URL は外部に POST するので https に限定する
  defp validate_webhook_url(changeset) do
    changeset
    |> validate_format(:webhook_url, ~r|^https://|, message: "https:// で始まる URL を指定してください")
    |> validate_length(:webhook_url, max: 500)
  end

  # AI プランは developer の Anthropic キーで生成するため、
  # キーが未登録なら生成が必ず失敗する。設定時点で弾く（→ docs/DECISIONS.md 3.1）
  defp validate_ai_plan_requires_anthropic_key(changeset, developer_scope) do
    if get_field(changeset, :plan) == :ai and
         is_nil(developer_scope.developer.anthropic_api_key) do
      add_error(
        changeset,
        :plan,
        "AI プランを使うには、先に Anthropic API キーを登録してください"
      )
    else
      changeset
    end
  end
end
