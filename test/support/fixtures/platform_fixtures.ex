defmodule AntPress.PlatformFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `AntPress.Platform` context.
  """

  import Ecto.Query

  alias AntPress.Platform
  alias AntPress.Platform.Scope

  def unique_developer_email, do: "developer#{System.unique_integer()}@example.com"
  def valid_developer_password, do: "hello world!"

  def valid_developer_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_developer_email(),
      name: "テスト制作所"
    })
  end

  def unconfirmed_developer_fixture(attrs \\ %{}) do
    {:ok, developer} =
      attrs
      |> valid_developer_attributes()
      |> Platform.create_developer()

    developer
  end

  def developer_fixture(attrs \\ %{}) do
    developer = unconfirmed_developer_fixture(attrs)

    token =
      extract_developer_token(fn url ->
        Platform.deliver_login_instructions(developer, url)
      end)

    {:ok, {developer, _expired_tokens}} =
      Platform.login_developer_by_magic_link(token)

    developer
  end

  def developer_scope_fixture do
    developer = developer_fixture()
    developer_scope_fixture(developer)
  end

  def developer_scope_fixture(%AntPress.Platform.Developer{} = developer) do
    Scope.for_developer(developer)
  end

  @doc """
  属性を指定して developer のスコープを作る。

      developer_scope_fixture(anthropic_api_key: "sk-ant-...")
  """
  def developer_scope_fixture(attrs) when is_list(attrs) or is_map(attrs) do
    developer = developer_fixture()

    developer =
      developer
      |> AntPress.Platform.Developer.profile_changeset(Map.new(attrs) |> stringify_keys())
      |> AntPress.Repo.update!()

    Scope.for_developer(developer)
  end

  @doc """
  admin（`role: :admin`）のスコープを作る。
  admin だけがテナントスコープを越えられる（→ docs/DATA-MODEL.md 1.1）。
  """
  def admin_scope_fixture(attrs \\ %{}) do
    {:ok, admin} =
      Platform.create_developer(
        valid_developer_attributes(Map.merge(%{role: :admin}, Map.new(attrs)))
      )

    Scope.for_developer(admin)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  def set_password(developer) do
    {:ok, {developer, _expired_tokens}} =
      Platform.update_developer_password(developer, %{password: valid_developer_password()})

    developer
  end

  def extract_developer_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    AntPress.Repo.update_all(
      from(t in Platform.DeveloperToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_developer_magic_link_token(developer) do
    {encoded_token, developer_token} =
      Platform.DeveloperToken.build_email_token(developer, "login")

    AntPress.Repo.insert!(developer_token)
    {encoded_token, developer_token.token}
  end

  def offset_developer_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    AntPress.Repo.update_all(
      from(ut in Platform.DeveloperToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  @doc """
  Generate a unique client slug.
  """
  def unique_client_slug, do: "client-#{System.unique_integer([:positive])}"

  @doc """
  Generate a client.
  """
  def client_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        contact_notification_email: "owner@example.com",
        name: "ラーメン太郎",
        plan: :basic,
        slug: unique_client_slug(),
        status: :active,
        webhook_url: "https://api.vercel.com/v1/integrations/deploy/abc123"
      })

    {:ok, client} = AntPress.Platform.create_client(scope, attrs)
    client
  end
end
