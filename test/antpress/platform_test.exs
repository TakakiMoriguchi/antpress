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
end
