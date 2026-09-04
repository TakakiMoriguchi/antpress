defmodule AntPress.Platform do
  @moduledoc """
  The Platform context.
  """

  import Ecto.Query, warn: false
  alias AntPress.Repo

  alias AntPress.Platform.{Developer, DeveloperToken, DeveloperNotifier}

  ## Database getters

  @doc """
  Gets a developer by email.

  ## Examples

      iex> get_developer_by_email("foo@example.com")
      %Developer{}

      iex> get_developer_by_email("unknown@example.com")
      nil

  """
  def get_developer_by_email(email) when is_binary(email) do
    Repo.get_by(Developer, email: email)
  end

  @doc """
  Gets a developer by email and password.

  ## Examples

      iex> get_developer_by_email_and_password("foo@example.com", "correct_password")
      %Developer{}

      iex> get_developer_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_developer_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    developer = Repo.get_by(Developer, email: email)
    if Developer.valid_password?(developer, password), do: developer
  end

  @doc """
  Gets a single developer.

  Raises `Ecto.NoResultsError` if the Developer does not exist.

  ## Examples

      iex> get_developer!(123)
      %Developer{}

      iex> get_developer!(456)
      ** (Ecto.NoResultsError)

  """
  def get_developer!(id), do: Repo.get!(Developer, id)

  ## Developer registration

  @doc """
  developer を新規作成する。

  **admin による発行、または seed からのみ呼ぶ。**
  antpress はセルフサインアップを一切行わない（→ docs/DECISIONS.md 1.3）。

  `role` を省略すると `:developer` になる。admin を作るのは seed のみ。

  ## Examples

      iex> create_developer(%{email: "dev@example.com", name: "山田制作所"})
      {:ok, %Developer{}}

  """
  def create_developer(attrs) do
    %Developer{}
    |> Developer.create_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the developer is in sudo mode.

  The developer is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(developer, minutes \\ -20)

  def sudo_mode?(%Developer{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_developer, _minutes), do: false

  @doc """
  屋号・氏名を変更するための changeset。
  """
  def change_developer_profile(%Developer{} = developer, attrs \\ %{}) do
    Developer.profile_changeset(developer, attrs)
  end

  @doc """
  屋号・氏名を更新する。

  `role` と `status` は含めない（誤って権限や契約状態を変えないため）。
  """
  def update_developer_profile(%Developer{} = developer, attrs) do
    developer
    |> Developer.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the developer email.

  See `AntPress.Platform.Developer.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_developer_email(developer)
      %Ecto.Changeset{data: %Developer{}}

  """
  def change_developer_email(developer, attrs \\ %{}, opts \\ []) do
    Developer.email_changeset(developer, attrs, opts)
  end

  @doc """
  Updates the developer email using the given token.

  If the token matches, the developer email is updated and the token is deleted.
  """
  def update_developer_email(developer, token) do
    context = "change:#{developer.email}"

    Repo.transact(fn ->
      with {:ok, query} <- DeveloperToken.verify_change_email_token_query(token, context),
           %DeveloperToken{sent_to: email} <- Repo.one(query),
           {:ok, developer} <- Repo.update(Developer.email_changeset(developer, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(
               from(DeveloperToken, where: [developer_id: ^developer.id, context: ^context])
             ) do
        {:ok, developer}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the developer password.

  See `AntPress.Platform.Developer.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_developer_password(developer)
      %Ecto.Changeset{data: %Developer{}}

  """
  def change_developer_password(developer, attrs \\ %{}, opts \\ []) do
    Developer.password_changeset(developer, attrs, opts)
  end

  @doc """
  Updates the developer password.

  Returns a tuple with the updated developer, as well as a list of expired tokens.

  ## Examples

      iex> update_developer_password(developer, %{password: ...})
      {:ok, {%Developer{}, [...]}}

      iex> update_developer_password(developer, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_developer_password(developer, attrs) do
    developer
    |> Developer.password_changeset(attrs)
    |> update_developer_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_developer_session_token(developer) do
    {token, developer_token} = DeveloperToken.build_session_token(developer)
    Repo.insert!(developer_token)
    token
  end

  @doc """
  Gets the developer with the given signed token.

  If the token is valid `{developer, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_developer_by_session_token(token) do
    {:ok, query} = DeveloperToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the developer with the given magic link token.
  """
  def get_developer_by_magic_link_token(token) do
    with {:ok, query} <- DeveloperToken.verify_magic_link_token_query(token),
         {developer, _token} <- Repo.one(query) do
      developer
    else
      _ -> nil
    end
  end

  @doc """
  Logs the developer in by magic link.

  There are three cases to consider:

  1. The developer has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The developer has not confirmed their email and no password is set.
     In this case, the developer gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The developer has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_developer_by_magic_link(token) do
    {:ok, query} = DeveloperToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%Developer{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%Developer{confirmed_at: nil} = developer, _token} ->
        developer
        |> Developer.confirm_changeset()
        |> update_developer_and_delete_all_tokens()

      {developer, token} ->
        Repo.delete!(token)
        {:ok, {developer, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given developer.

  ## Examples

      iex> deliver_developer_update_email_instructions(developer, current_email, &url(~p"/developers/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_developer_update_email_instructions(
        %Developer{} = developer,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, developer_token} =
      DeveloperToken.build_email_token(developer, "change:#{current_email}")

    Repo.insert!(developer_token)

    DeveloperNotifier.deliver_update_email_instructions(
      developer,
      update_email_url_fun.(encoded_token)
    )
  end

  @doc """
  Delivers the magic link login instructions to the given developer.
  """
  def deliver_login_instructions(%Developer{} = developer, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, developer_token} = DeveloperToken.build_email_token(developer, "login")
    Repo.insert!(developer_token)
    DeveloperNotifier.deliver_login_instructions(developer, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_developer_session_token(token) do
    Repo.delete_all(from(DeveloperToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_developer_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, developer} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(DeveloperToken, developer_id: developer.id)

        Repo.delete_all(
          from(t in DeveloperToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id))
        )

        {:ok, {developer, tokens_to_expire}}
      end
    end)
  end

  alias AntPress.Platform.Client
  alias AntPress.Platform.Scope

  @doc """
  Subscribes to scoped notifications about any client changes.

  The broadcasted messages match the pattern:

    * {:created, %Client{}}
    * {:updated, %Client{}}
    * {:deleted, %Client{}}

  """
  def subscribe_clients(%Scope{} = scope) do
    key = scope.developer.id

    Phoenix.PubSub.subscribe(AntPress.PubSub, "developer:#{key}:clients")
  end

  defp broadcast_client(%Scope{} = scope, message) do
    key = scope.developer.id

    Phoenix.PubSub.broadcast(AntPress.PubSub, "developer:#{key}:clients", message)
  end

  @doc """
  Returns the list of clients.

  ## Examples

      iex> list_clients(scope)
      [%Client{}, ...]

  """
  def list_clients(%Scope{developer: %Developer{role: :admin}}) do
    Repo.all(Client)
  end

  def list_clients(%Scope{} = scope) do
    Repo.all_by(Client, developer_id: scope.developer.id)
  end

  @doc """
  Gets a single client.

  Raises `Ecto.NoResultsError` if the Client does not exist.

  ## Examples

      iex> get_client!(scope, 123)
      %Client{}

      iex> get_client!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_client!(%Scope{developer: %Developer{role: :admin}}, id) do
    Repo.get!(Client, id)
  end

  def get_client!(%Scope{} = scope, id) do
    Repo.get_by!(Client, id: id, developer_id: scope.developer.id)
  end

  @doc """
  Creates a client.

  ## Examples

      iex> create_client(scope, %{field: value})
      {:ok, %Client{}}

      iex> create_client(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_client(%Scope{} = scope, attrs) do
    with {:ok, client = %Client{}} <-
           %Client{}
           |> Client.changeset(attrs, scope)
           |> Repo.insert() do
      # 空の状態からカテゴリを作らせないため、業種横断のプリセットを投入する
      # （→ docs/DECISIONS.md 3.2）
      {:ok, _count} = AntPress.Blog.seed_categories(client)

      broadcast_client(scope, {:created, client})
      {:ok, client}
    end
  end

  @doc """
  Updates a client.

  ## Examples

      iex> update_client(scope, client, %{field: new_value})
      {:ok, %Client{}}

      iex> update_client(scope, client, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_client(%Scope{} = scope, %Client{} = client, attrs) do
    :ok = authorize_client!(scope, client)

    with {:ok, client = %Client{}} <-
           client
           |> Client.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_client(scope, {:updated, client})
      {:ok, client}
    end
  end

  @doc """
  Deletes a client.

  ## Examples

      iex> delete_client(scope, client)
      {:ok, %Client{}}

      iex> delete_client(scope, client)
      {:error, %Ecto.Changeset{}}

  """
  def delete_client(%Scope{} = scope, %Client{} = client) do
    :ok = authorize_client!(scope, client)

    with {:ok, client = %Client{}} <-
           Repo.delete(client) do
      broadcast_client(scope, {:deleted, client})
      {:ok, client}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking client changes.

  ## Examples

      iex> change_client(scope, client)
      %Ecto.Changeset{data: %Client{}}

  """
  def change_client(%Scope{} = scope, %Client{} = client, attrs \\ %{}) do
    :ok = authorize_client!(scope, client)

    Client.changeset(client, attrs, scope)
  end

  # ⚠️ テナント分離の最終防衛線。
  # admin だけがスコープを越えられる（→ docs/DATA-MODEL.md 1.1）。
  # 一致しなければ MatchError で即座に落ちる（無言で通さない）。
  defp authorize_client!(%Scope{developer: %Developer{role: :admin}}, %Client{}), do: :ok

  defp authorize_client!(%Scope{developer: %Developer{id: dev_id}}, %Client{
         developer_id: dev_id
       }),
       do: :ok
end
