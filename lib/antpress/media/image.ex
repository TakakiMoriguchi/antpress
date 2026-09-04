defmodule AntPress.Media.Image do
  @moduledoc """
  アップロードされた画像のメタデータ。

  **ファイル本体は持たない。** 本体はオブジェクトストレージにあり、
  ここは `storage_path` で指しているだけ（→ `docs/DATA-MODEL.md` 3.9）。

  ## ユーザーが編集できるのは `alt_text` だけ

  それ以外の列（`storage_path` / `content_type` / `byte_size` / `width` /
  `height`）は**アップロードしたファイルから antpress が決める**。
  だから changeset を 2 つに分けている。

  * `create_changeset/3` — アップロード時。antpress が組んだ attrs を受ける
  * `alt_text_changeset/2` — 画面からの編集。`alt_text` しか cast しない

  1 つの changeset で全部 cast すると、フォームに隠しフィールドを足すだけで
  `storage_path` を他クライアントのパスに書き換えられてしまう。
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AntPress.Platform.Client

  # SVG は入れない。スクリプトを埋め込めるため、同一オリジンで配信すると
  # XSS になる（開発環境はローカル配信なので実際に同一オリジンになる）
  @content_types ~w(image/jpeg image/png image/gif image/webp)

  # 拡張子は content_type から決める。**アップロード時のファイル名は使わない**
  @extension_for %{
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/gif" => "gif",
    "image/webp" => "webp"
  }

  # 小規模 HP に載せる画像を想定した上限。
  # 重い画像は表示速度（=SEO）に直接響くので、そもそも上げさせない
  @max_byte_size 5_000_000

  @doc "許可する MIME タイプ"
  def content_types, do: @content_types

  @doc "`live_file_input` の `accept` に渡す拡張子"
  def extensions, do: ~w(.jpg .jpeg .png .gif .webp)

  @doc "1 ファイルの上限バイト数"
  def max_byte_size, do: @max_byte_size

  @doc "MIME タイプに対応する拡張子。未対応なら `nil`"
  def extension_for(content_type), do: Map.get(@extension_for, content_type)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "images" do
    # ストレージ内のパス。`clients/{client_id}/{uuid}.{ext}`
    field :storage_path, :string

    # アップロード時の元ファイル名。一覧での見分けにのみ使う
    field :filename, :string

    field :content_type, :string
    field :byte_size, :integer
    field :width, :integer
    field :height, :integer

    # 代替テキスト。未設定でもアップロードは通す（後から設定できる）
    field :alt_text, :string

    belongs_to :client, Client

    # ⚠️ マイクロ秒精度。まとめてアップロードした画像の並び順を保つため
    # （→ マイグレーションの注記）
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  アップロード時の changeset。

  ⚠️ `client_id` は cast しない。スコープから設定する。
  """
  def create_changeset(image, attrs, client_scope) do
    image
    |> cast(attrs, [
      :storage_path,
      :filename,
      :content_type,
      :byte_size,
      :width,
      :height,
      :alt_text
    ])
    |> validate_required([:storage_path, :filename, :content_type, :byte_size])
    |> validate_inclusion(:content_type, @content_types,
      message: "対応していない画像形式です（JPEG / PNG / GIF / WebP）"
    )
    |> validate_number(:byte_size,
      greater_than: 0,
      less_than_or_equal_to: @max_byte_size,
      message: "ファイルサイズが上限（#{div(@max_byte_size, 1_000_000)}MB）を超えています"
    )
    |> validate_length(:filename, max: 255)
    |> validate_alt_text()
    |> unique_constraint(:storage_path)
    # ⚠️ raise ではなく changeset エラーにする。
    # DB 挿入が失敗したら Media 側がストレージ上のオブジェクトを消すので、
    # 例外で飛ばすとその後始末が走らない
    |> foreign_key_constraint(:client_id)
    |> check_constraint(:content_type,
      name: :images_content_type_must_be_supported_image,
      message: "対応していない画像形式です"
    )
    |> put_client_id(client_scope)
  end

  @doc """
  画面からの編集。**`alt_text` しか変更できない。**
  """
  def alt_text_changeset(image, attrs) do
    image
    |> cast(attrs, [:alt_text])
    |> validate_alt_text()
  end

  # 長い alt は読み上げの妨げになり、検索エンジンにも詰め込みと見なされる
  defp validate_alt_text(changeset) do
    validate_length(changeset, :alt_text, max: 200)
  end

  # ⚠️ `client_id` は**作成時のみ**設定する（→ blog/category.ex に同じ注記）。
  defp put_client_id(changeset, client_scope) do
    case changeset.data.client_id do
      nil -> put_change(changeset, :client_id, client_scope.client.id)
      _existing -> changeset
    end
  end
end
