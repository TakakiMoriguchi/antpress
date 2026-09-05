defmodule AntPress.Blog.Category do
  @moduledoc """
  ブログのカテゴリ。

  **1 記事 1 カテゴリ**（複数選択にはしない → `docs/DECISIONS.md` 3.2）。
  クライアントが自由に作成・編集できるが、クライアント作成時に
  業種横断のプリセットを投入して空の状態から作らせない。

  タグは作らない（→ `docs/DATA-MODEL.md` 1.6）。
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AntPress.Platform.Client

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blog_categories" do
    field :name, :string

    # 記事 URL に使う。一意性はクライアント単位
    field :slug, :string

    # 表示順
    field :position, :integer, default: 0

    belongs_to :client, Client

    timestamps(type: :utc_datetime)
  end

  @doc """
  カテゴリの changeset。

  ⚠️ `client_id` は `cast` しない。スコープから設定する。
  attrs から受け取ると、他クライアント配下にカテゴリを作れてしまう。
  """
  def changeset(category, attrs, client_scope) do
    category
    |> cast(attrs, [:name, :slug, :position])
    |> validate_required([:name, :slug])
    |> validate_length(:name, max: 60)
    |> validate_slug()
    |> unique_constraint([:client_id, :slug],
      name: :blog_categories_client_id_slug_index,
      message: "このアドレスは既に使われています"
    )
    |> put_client_id(client_scope)
  end

  # 記事 URL に使うので英小文字・数字・ハイフンのみ。
  # ⚠️ 画面では「スラッグ」と呼ばない（→ blog/article.ex に同じ注記）
  defp validate_slug(changeset) do
    changeset
    |> validate_length(:slug, min: 1, max: 60)
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "半角の英字（小文字）・数字・ハイフンだけが使えます（先頭と末尾にハイフンは使えません）"
    )
  end

  # ⚠️ `client_id` は**作成時のみ**設定する。
  #
  # 無条件に `put_change` すると、所有者を書き換えられてしまう
  # （clients で同型のバグを実際に検出した → docs/DATA-MODEL.md 参照）。
  defp put_client_id(changeset, client_scope) do
    case changeset.data.client_id do
      nil -> put_change(changeset, :client_id, client_scope.client.id)
      _existing -> changeset
    end
  end
end
