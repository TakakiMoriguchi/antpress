defmodule AntPress.Platform.Developer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "developers" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    # ─── antpress 固有 ───────────────────────────────
    # admin 自身も developer レコードを持つ（→ docs/DECISIONS.md 1.3）
    field :role, Ecto.Enum, values: [:admin, :developer], default: :developer
    field :name, :string

    # ⚠️ 暗号化して保存（ハッシュ不可）。redact でログ・inspect から除外する
    field :anthropic_api_key, AntPress.Encrypted.Binary, redact: true

    field :status, Ecto.Enum, values: [:active, :suspended], default: :active
    field :note, :string

    # NOTE: has_many :clients は AntPress.Platform.Client 作成後（実装順序 2）に追加する

    timestamps(type: :utc_datetime)
  end

  @doc """
  developer を新規作成するための changeset。

  **admin による発行、または seed からのみ使う。**
  セルフサインアップは行わない（→ docs/DECISIONS.md 1.3）。
  """
  def create_changeset(developer, attrs, opts \\ []) do
    developer
    |> cast(attrs, [:email, :name, :role])
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
    |> validate_email(opts)
  end

  @doc """
  developer の設定（名前・メモ・Anthropic キー）を更新する changeset。

  `role` と `status` は含めない。誤って権限や契約状態を変えないよう、
  それぞれ専用の関数を使う。
  """
  def profile_changeset(developer, attrs) do
    developer
    |> cast(attrs, [:name, :anthropic_api_key, :note])
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
  end

  @doc """
  admin が developer を停止・再開する changeset。

  ⚠️ `suspended` にすると管理画面ログインと配信 API の**両方**が止まる
  （→ docs/DECISIONS.md 3.10）。
  """
  def status_changeset(developer, attrs) do
    cast(developer, attrs, [:status])
  end

  @doc """
  admin かどうか。スコープを越えられるのは admin だけ
  （→ docs/DATA-MODEL.md 1.1）。
  """
  def admin?(%__MODULE__{role: :admin}), do: true
  def admin?(%__MODULE__{}), do: false

  @doc """
  A developer changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(developer, attrs, opts \\ []) do
    developer
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, AntPress.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A developer changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(developer, attrs, opts \\ []) do
    developer
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(developer) do
    now = DateTime.utc_now(:second)
    change(developer, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no developer or the developer doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%AntPress.Platform.Developer{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
