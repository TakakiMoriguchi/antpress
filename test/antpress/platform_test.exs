defmodule AntPress.PlatformTest do
  use AntPress.DataCase

  alias AntPress.Platform

  import AntPress.PlatformFixtures
  alias AntPress.Platform.{Developer, DeveloperToken}

  describe "get_developer_by_email/1" do
    test "does not return the developer if the email does not exist" do
      refute Platform.get_developer_by_email("unknown@example.com")
    end

    test "returns the developer if the email exists" do
      %{id: id} = developer = developer_fixture()
      assert %Developer{id: ^id} = Platform.get_developer_by_email(developer.email)
    end
  end

  describe "get_developer_by_email_and_password/2" do
    test "does not return the developer if the email does not exist" do
      refute Platform.get_developer_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the developer if the password is not valid" do
      developer = developer_fixture() |> set_password()
      refute Platform.get_developer_by_email_and_password(developer.email, "invalid")
    end

    test "returns the developer if the email and password are valid" do
      %{id: id} = developer = developer_fixture() |> set_password()

      assert %Developer{id: ^id} =
               Platform.get_developer_by_email_and_password(
                 developer.email,
                 valid_developer_password()
               )
    end
  end

  describe "get_developer!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Platform.get_developer!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the developer with the given id" do
      %{id: id} = developer = developer_fixture()
      assert %Developer{id: ^id} = Platform.get_developer!(developer.id)
    end
  end

  describe "create_developer/1" do
    test "メールと名前を要求する" do
      {:error, changeset} = Platform.create_developer(%{})

      assert %{
               email: ["can't be blank"],
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "メール形式と名前の長さを検証する" do
      {:error, changeset} =
        Platform.create_developer(%{email: "not valid", name: String.duplicate("あ", 200)})

      assert %{
               email: ["must have the @ sign and no spaces"],
               name: ["should be at most 160 character(s)"]
             } = errors_on(changeset)
    end

    test "メールの最大長を検証する" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Platform.create_developer(%{email: too_long, name: "テスト"})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "メールの一意性を検証する（大文字小文字を区別しない）" do
      %{email: email} = developer_fixture()
      {:error, changeset} = Platform.create_developer(%{email: email, name: "テスト"})
      assert "has already been taken" in errors_on(changeset).email

      {:error, changeset} =
        Platform.create_developer(%{email: String.upcase(email), name: "テスト"})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "パスワード・確認済み日時なしで作成され、既定は role: :developer / status: :active" do
      email = unique_developer_email()
      {:ok, developer} = Platform.create_developer(valid_developer_attributes(email: email))

      assert developer.email == email
      assert developer.name == "テスト制作所"
      assert developer.role == :developer
      assert developer.status == :active
      assert is_nil(developer.hashed_password)
      assert is_nil(developer.confirmed_at)
      assert is_nil(developer.password)
    end

    test "role: :admin を指定して作成できる（seed 用）" do
      {:ok, developer} =
        Platform.create_developer(valid_developer_attributes(role: :admin))

      assert developer.role == :admin
      assert AntPress.Platform.Developer.admin?(developer)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Platform.sudo_mode?(%Developer{authenticated_at: DateTime.utc_now()})
      assert Platform.sudo_mode?(%Developer{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Platform.sudo_mode?(%Developer{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Platform.sudo_mode?(
               %Developer{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Platform.sudo_mode?(%Developer{})
    end
  end

  describe "change_developer_email/3" do
    test "returns a developer changeset" do
      assert %Ecto.Changeset{} = changeset = Platform.change_developer_email(%Developer{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_developer_update_email_instructions/3" do
    setup do
      %{developer: developer_fixture()}
    end

    test "sends token through notification", %{developer: developer} do
      token =
        extract_developer_token(fn url ->
          Platform.deliver_developer_update_email_instructions(
            developer,
            "current@example.com",
            url
          )
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert developer_token = Repo.get_by(DeveloperToken, token: :crypto.hash(:sha256, token))
      assert developer_token.developer_id == developer.id
      assert developer_token.sent_to == developer.email
      assert developer_token.context == "change:current@example.com"
    end
  end

  describe "update_developer_email/2" do
    setup do
      developer = unconfirmed_developer_fixture()
      email = unique_developer_email()

      token =
        extract_developer_token(fn url ->
          Platform.deliver_developer_update_email_instructions(
            %{developer | email: email},
            developer.email,
            url
          )
        end)

      %{developer: developer, token: token, email: email}
    end

    test "updates the email with a valid token", %{
      developer: developer,
      token: token,
      email: email
    } do
      assert {:ok, %{email: ^email}} = Platform.update_developer_email(developer, token)
      changed_developer = Repo.get!(Developer, developer.id)
      assert changed_developer.email != developer.email
      assert changed_developer.email == email
      refute Repo.get_by(DeveloperToken, developer_id: developer.id)
    end

    test "does not update email with invalid token", %{developer: developer} do
      assert Platform.update_developer_email(developer, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(Developer, developer.id).email == developer.email
      assert Repo.get_by(DeveloperToken, developer_id: developer.id)
    end

    test "does not update email if developer email changed", %{developer: developer, token: token} do
      assert Platform.update_developer_email(%{developer | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(Developer, developer.id).email == developer.email
      assert Repo.get_by(DeveloperToken, developer_id: developer.id)
    end

    test "does not update email if token expired", %{developer: developer, token: token} do
      {1, nil} = Repo.update_all(DeveloperToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Platform.update_developer_email(developer, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(Developer, developer.id).email == developer.email
      assert Repo.get_by(DeveloperToken, developer_id: developer.id)
    end
  end

  describe "change_developer_password/3" do
    test "returns a developer changeset" do
      assert %Ecto.Changeset{} = changeset = Platform.change_developer_password(%Developer{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Platform.change_developer_password(
          %Developer{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_developer_password/2" do
    setup do
      %{developer: developer_fixture()}
    end

    test "validates password", %{developer: developer} do
      {:error, changeset} =
        Platform.update_developer_password(developer, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{developer: developer} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Platform.update_developer_password(developer, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{developer: developer} do
      {:ok, {developer, expired_tokens}} =
        Platform.update_developer_password(developer, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(developer.password)
      assert Platform.get_developer_by_email_and_password(developer.email, "new valid password")
    end

    test "deletes all tokens for the given developer", %{developer: developer} do
      _ = Platform.generate_developer_session_token(developer)

      {:ok, {_, _}} =
        Platform.update_developer_password(developer, %{
          password: "new valid password"
        })

      refute Repo.get_by(DeveloperToken, developer_id: developer.id)
    end
  end

  describe "generate_developer_session_token/1" do
    setup do
      %{developer: developer_fixture()}
    end

    test "generates a token", %{developer: developer} do
      token = Platform.generate_developer_session_token(developer)
      assert developer_token = Repo.get_by(DeveloperToken, token: token)
      assert developer_token.context == "session"
      assert developer_token.authenticated_at != nil

      # Creating the same token for another developer should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%DeveloperToken{
          token: developer_token.token,
          developer_id: developer_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given developer in new token", %{
      developer: developer
    } do
      developer = %{developer | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Platform.generate_developer_session_token(developer)
      assert developer_token = Repo.get_by(DeveloperToken, token: token)
      assert developer_token.authenticated_at == developer.authenticated_at
      assert DateTime.compare(developer_token.inserted_at, developer.authenticated_at) == :gt
    end
  end

  describe "get_developer_by_session_token/1" do
    setup do
      developer = developer_fixture()
      token = Platform.generate_developer_session_token(developer)
      %{developer: developer, token: token}
    end

    test "returns developer by token", %{developer: developer, token: token} do
      assert {session_developer, token_inserted_at} =
               Platform.get_developer_by_session_token(token)

      assert session_developer.id == developer.id
      assert session_developer.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return developer for invalid token" do
      refute Platform.get_developer_by_session_token("oops")
    end

    test "does not return developer for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(DeveloperToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Platform.get_developer_by_session_token(token)
    end
  end

  describe "get_developer_by_magic_link_token/1" do
    setup do
      developer = developer_fixture()
      {encoded_token, _hashed_token} = generate_developer_magic_link_token(developer)
      %{developer: developer, token: encoded_token}
    end

    test "returns developer by token", %{developer: developer, token: token} do
      assert session_developer = Platform.get_developer_by_magic_link_token(token)
      assert session_developer.id == developer.id
    end

    test "does not return developer for invalid token" do
      refute Platform.get_developer_by_magic_link_token("oops")
    end

    test "does not return developer for expired token", %{token: token} do
      {1, nil} = Repo.update_all(DeveloperToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Platform.get_developer_by_magic_link_token(token)
    end
  end

  describe "login_developer_by_magic_link/1" do
    test "confirms developer and expires tokens" do
      developer = unconfirmed_developer_fixture()
      refute developer.confirmed_at
      {encoded_token, hashed_token} = generate_developer_magic_link_token(developer)

      assert {:ok, {developer, [%{token: ^hashed_token}]}} =
               Platform.login_developer_by_magic_link(encoded_token)

      assert developer.confirmed_at
    end

    test "returns developer and (deleted) token for confirmed developer" do
      developer = developer_fixture()
      assert developer.confirmed_at
      {encoded_token, _hashed_token} = generate_developer_magic_link_token(developer)
      assert {:ok, {^developer, []}} = Platform.login_developer_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Platform.login_developer_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed developer has password set" do
      developer = unconfirmed_developer_fixture()
      {1, nil} = Repo.update_all(Developer, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_developer_magic_link_token(developer)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Platform.login_developer_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_developer_session_token/1" do
    test "deletes the token" do
      developer = developer_fixture()
      token = Platform.generate_developer_session_token(developer)
      assert Platform.delete_developer_session_token(token) == :ok
      refute Platform.get_developer_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{developer: unconfirmed_developer_fixture()}
    end

    test "sends token through notification", %{developer: developer} do
      token =
        extract_developer_token(fn url ->
          Platform.deliver_login_instructions(developer, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert developer_token = Repo.get_by(DeveloperToken, token: :crypto.hash(:sha256, token))
      assert developer_token.developer_id == developer.id
      assert developer_token.sent_to == developer.email
      assert developer_token.context == "login"
    end
  end

  describe "inspect/2 for the Developer module" do
    test "does not include password" do
      refute inspect(%Developer{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "clients" do
    alias AntPress.Platform.Client

    import AntPress.PlatformFixtures, only: [developer_scope_fixture: 0]
    import AntPress.PlatformFixtures

    @invalid_attrs %{
      name: nil,
      status: nil,
      plan: nil,
      slug: nil,
      contact_notification_email: nil,
      webhook_url: nil
    }

    test "list_clients/1 returns all scoped clients" do
      scope = developer_scope_fixture()
      other_scope = developer_scope_fixture()
      client = client_fixture(scope)
      other_client = client_fixture(other_scope)
      assert Platform.list_clients(scope) == [client]
      assert Platform.list_clients(other_scope) == [other_client]
    end

    test "get_client!/2 returns the client with given id" do
      scope = developer_scope_fixture()
      client = client_fixture(scope)
      other_scope = developer_scope_fixture()
      assert Platform.get_client!(scope, client.id) == client
      assert_raise Ecto.NoResultsError, fn -> Platform.get_client!(other_scope, client.id) end
    end

    test "create_client/2 with valid data creates a client" do
      valid_attrs = %{
        name: "ラーメン太郎",
        status: :active,
        plan: :basic,
        slug: "ramen-taro",
        contact_notification_email: "owner@example.com",
        webhook_url: "https://api.vercel.com/v1/deploy/abc"
      }

      scope = developer_scope_fixture()

      assert {:ok, %Client{} = client} = Platform.create_client(scope, valid_attrs)
      assert client.name == "ラーメン太郎"
      assert client.status == :active
      assert client.plan == :basic
      assert client.slug == "ramen-taro"
      assert client.contact_notification_email == "owner@example.com"
      assert client.webhook_url == "https://api.vercel.com/v1/deploy/abc"
      assert client.developer_id == scope.developer.id
    end

    test "create_client/2 with invalid data returns error changeset" do
      scope = developer_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Platform.create_client(scope, @invalid_attrs)
    end

    test "update_client/3 with valid data updates the client" do
      scope = developer_scope_fixture()
      client = client_fixture(scope)
      # plan は :basic のまま。AI プランは developer の Anthropic キー登録が前提
      # （→ docs/DECISIONS.md 3.1）。専用のテストで検証する
      update_attrs = %{
        name: "ラーメン太郎 本店",
        status: :suspended,
        plan: :basic,
        slug: "ramen-taro-honten",
        contact_notification_email: "owner2@example.com",
        webhook_url: "https://api.vercel.com/v1/deploy/xyz"
      }

      assert {:ok, %Client{} = client} = Platform.update_client(scope, client, update_attrs)
      assert client.name == "ラーメン太郎 本店"
      assert client.status == :suspended
      assert client.plan == :basic
      assert client.slug == "ramen-taro-honten"
      assert client.contact_notification_email == "owner2@example.com"
      assert client.webhook_url == "https://api.vercel.com/v1/deploy/xyz"
    end

    test "update_client/3 with invalid scope raises" do
      scope = developer_scope_fixture()
      other_scope = developer_scope_fixture()
      client = client_fixture(scope)

      assert_raise FunctionClauseError, fn ->
        Platform.update_client(other_scope, client, %{})
      end
    end

    test "update_client/3 with invalid data returns error changeset" do
      scope = developer_scope_fixture()
      client = client_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Platform.update_client(scope, client, @invalid_attrs)
      assert client == Platform.get_client!(scope, client.id)
    end

    test "delete_client/2 deletes the client" do
      scope = developer_scope_fixture()
      client = client_fixture(scope)
      assert {:ok, %Client{}} = Platform.delete_client(scope, client)
      assert_raise Ecto.NoResultsError, fn -> Platform.get_client!(scope, client.id) end
    end

    test "delete_client/2 with invalid scope raises" do
      scope = developer_scope_fixture()
      other_scope = developer_scope_fixture()
      client = client_fixture(scope)
      assert_raise FunctionClauseError, fn -> Platform.delete_client(other_scope, client) end
    end

    # ─── ここから antpress 固有の設計要件のテスト ───────────────

    test "admin はスコープを越えて全クライアントを取得できる（→ docs/DATA-MODEL.md 1.1）" do
      dev_scope = developer_scope_fixture()
      other_scope = developer_scope_fixture()
      admin_scope = admin_scope_fixture()

      client_a = client_fixture(dev_scope)
      client_b = client_fixture(other_scope)

      # developer は自分のものだけ
      assert Platform.list_clients(dev_scope) == [client_a]
      assert Platform.list_clients(other_scope) == [client_b]

      # admin は全件
      admin_ids = Platform.list_clients(admin_scope) |> Enum.map(& &1.id) |> Enum.sort()
      assert admin_ids == Enum.sort([client_a.id, client_b.id])

      # admin は他人のクライアントを個別取得できる
      assert Platform.get_client!(admin_scope, client_a.id).id == client_a.id
      assert Platform.get_client!(admin_scope, client_b.id).id == client_b.id
    end

    test "developer は他の developer のクライアントを取得できない" do
      dev_scope = developer_scope_fixture()
      other_scope = developer_scope_fixture()
      client = client_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        Platform.get_client!(dev_scope, client.id)
      end
    end

    test "admin は他人のクライアントを更新・削除できる" do
      dev_scope = developer_scope_fixture()
      admin_scope = admin_scope_fixture()
      client = client_fixture(dev_scope)

      assert {:ok, updated} = Platform.update_client(admin_scope, client, %{name: "admin が改名"})
      assert updated.name == "admin が改名"

      # developer_id は元の developer のまま（admin に付け替わらない）
      assert updated.developer_id == dev_scope.developer.id

      assert {:ok, _} = Platform.delete_client(admin_scope, updated)
    end

    test "developer_id は attrs から設定できない（他人配下に作れない）" do
      dev_scope = developer_scope_fixture()
      other_scope = developer_scope_fixture()

      attrs = %{
        name: "乗っ取り試行",
        slug: "hijack-attempt",
        plan: :basic,
        developer_id: other_scope.developer.id
      }

      assert {:ok, client} = Platform.create_client(dev_scope, attrs)

      # スコープ側の developer_id が採用され、attrs は無視される
      assert client.developer_id == dev_scope.developer.id
      refute client.developer_id == other_scope.developer.id
    end

    test "Anthropic キー未登録の developer は AI プランを設定できない（→ docs/DECISIONS.md 3.1）" do
      scope = developer_scope_fixture()
      refute scope.developer.anthropic_api_key

      assert {:error, changeset} =
               Platform.create_client(scope, %{name: "AI 希望", slug: "ai-hope", plan: :ai})

      assert "AI プランを使うには、先に Anthropic API キーを登録してください" in errors_on(changeset).plan
    end

    test "Anthropic キー登録済みの developer は AI プランを設定できる" do
      scope = developer_scope_fixture(anthropic_api_key: "sk-ant-test-key")
      assert scope.developer.anthropic_api_key

      assert {:ok, client} =
               Platform.create_client(scope, %{name: "AI 利用", slug: "ai-ok", plan: :ai})

      assert client.plan == :ai
    end

    test "スラッグは英小文字・数字・ハイフンのみ" do
      scope = developer_scope_fixture()

      for bad <- ["Upper", "with space", "-leading", "trailing-", "under_score", "日本語"] do
        assert {:error, changeset} =
                 Platform.create_client(scope, %{name: "n", slug: bad, plan: :basic})

        assert Map.has_key?(errors_on(changeset), :slug), "#{bad} が通ってしまった"
      end
    end

    test "webhook_url は https のみ" do
      scope = developer_scope_fixture()

      assert {:error, changeset} =
               Platform.create_client(scope, %{
                 name: "n",
                 slug: "http-webhook",
                 plan: :basic,
                 webhook_url: "http://example.com/hook"
               })

      assert "https:// で始まる URL を指定してください" in errors_on(changeset).webhook_url
    end

    test "スラッグはグローバル一意（別 developer 間でも重複不可）" do
      scope = developer_scope_fixture()
      other_scope = developer_scope_fixture()

      assert {:ok, _} = Platform.create_client(scope, %{name: "a", slug: "dup", plan: :basic})

      assert {:error, changeset} =
               Platform.create_client(other_scope, %{name: "b", slug: "dup", plan: :basic})

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "change_client/2 returns a client changeset" do
      scope = developer_scope_fixture()
      client = client_fixture(scope)
      assert %Ecto.Changeset{} = Platform.change_client(scope, client)
    end
  end
end
