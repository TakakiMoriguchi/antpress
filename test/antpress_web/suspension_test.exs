defmodule AntPressWeb.SuspensionTest do
  @moduledoc """
  停止（`status = :suspended`）が実際に利用を止めることを固定する。

  ⚠️ **これが効かないと課金コントロールの手段が無い**
  （→ `docs/DECISIONS.md` 3.10）。実装前は status を変えても
  ログインも既存セッションも通っていた。
  """
  use AntPressWeb.ConnCase

  import Phoenix.LiveViewTest
  import AntPress.AccountsFixtures
  import AntPress.PlatformFixtures

  alias AntPress.{Accounts, Platform}

  # ⚠️ user_fixture が返す client には developer が入っていない
  defp dev_scope(user) do
    client = AntPress.Repo.preload(user.client, :developer)
    Platform.Scope.for_developer(client.developer)
  end

  defp suspend_client(user) do
    {:ok, _} = Platform.update_client(dev_scope(user), user.client, %{status: :suspended})
  end

  # オーナーは自分を止められないので、停止操作は developer スコープで行う
  defp suspend_user(user) do
    {:ok, updated} = Accounts.update_user_status(dev_scope(user), user, %{status: :suspended})
    %{updated | client: user.client}
  end

  describe "クライアント側" do
    test "停止していなければ使える", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:ok, _lv, _html} = live(conn, ~p"/client/articles")
    end

    test "⚠️ ユーザーを停止すると既存セッションでも入れない", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      # 先にログインしておいてから停止する
      suspend_user(user)

      assert {:error, {:redirect, %{to: "/client/log-in", flash: flash}}} =
               live(conn, ~p"/client/articles")

      assert flash["error"] =~ "このアカウントは停止されています"
    end

    test "⚠️ クライアントを停止すると配下のユーザーが入れない", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      suspend_client(user)

      assert {:error, {:redirect, %{to: "/client/log-in", flash: flash}}} =
               live(conn, ~p"/client/articles")

      assert flash["error"] =~ "ご利用が停止されています"
    end

    test "⚠️ developer を停止すると配下のクライアントが入れない", %{conn: conn} do
      # これが課金コントロールの本体。developer 1 件の操作で配下が全部止まる
      user = user_fixture()
      conn = log_in_user(conn, user)

      admin_scope = admin_scope_fixture()

      {:ok, _} =
        Platform.update_developer_status(
          admin_scope,
          AntPress.Repo.preload(user.client, :developer).developer,
          %{status: :suspended}
        )

      assert {:error, {:redirect, %{to: "/client/log-in", flash: flash}}} =
               live(conn, ~p"/client/articles")

      assert flash["error"] =~ "ご利用が停止されています"
    end

    test "停止中は新しくログインもできない", %{conn: conn} do
      user = user_fixture()
      suspend_user(user)

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/client/articles")

      assert redirected_to(conn) == ~p"/client/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "停止されています"
    end
  end

  describe "developer 側" do
    test "停止していなければ使える", %{conn: conn} do
      conn = log_in_developer(conn, developer_fixture())

      assert {:ok, _lv, _html} = live(conn, ~p"/clients")
    end

    test "⚠️ 停止すると既存セッションでも入れない", %{conn: conn} do
      developer = developer_fixture()
      conn = log_in_developer(conn, developer)

      {:ok, _} =
        Platform.update_developer_status(admin_scope_fixture(), developer, %{
          status: :suspended
        })

      assert {:error, {:redirect, %{to: "/developers/log-in", flash: flash}}} =
               live(conn, ~p"/clients")

      assert flash["error"] =~ "運営者にお問い合わせください"
    end
  end

  describe "⚠️ 誰が誰を停止できるか" do
    test "オーナーは同じクライアントのスタッフを停止できる" do
      owner = user_fixture(%{role: :owner})
      staff = user_fixture(%{role: :staff, client: owner.client})
      scope = Accounts.Scope.for_user(owner)

      assert {:ok, updated} = Accounts.update_user_status(scope, staff, %{status: :suspended})
      assert updated.status == :suspended
    end

    test "⚠️ スタッフは誰も停止できない" do
      staff = user_fixture(%{role: :staff})
      other = user_fixture(%{role: :staff, client: staff.client})
      scope = Accounts.Scope.for_user(staff)

      assert {:error, :unauthorized} =
               Accounts.update_user_status(scope, other, %{status: :suspended})
    end

    test "⚠️ オーナーは自分自身を停止できない" do
      owner = user_fixture(%{role: :owner})
      scope = Accounts.Scope.for_user(owner)

      assert {:error, :cannot_suspend_self} =
               Accounts.update_user_status(scope, owner, %{status: :suspended})
    end

    test "⚠️ オーナーは他のオーナーを停止できない" do
      # オーナーを発行するのは developer なので、停止も developer の役目
      owner = user_fixture(%{role: :owner})
      other_owner = user_fixture(%{role: :owner, client: owner.client})
      scope = Accounts.Scope.for_user(owner)

      assert {:error, :unauthorized} =
               Accounts.update_user_status(scope, other_owner, %{status: :suspended})
    end

    test "⚠️ オーナーは他クライアントのスタッフを停止できない" do
      owner = user_fixture(%{role: :owner})
      other_staff = user_fixture(%{role: :staff})
      scope = Accounts.Scope.for_user(owner)

      assert {:error, :unauthorized} =
               Accounts.update_user_status(scope, other_staff, %{status: :suspended})
    end

    test "developer は自分の配下のオーナーを停止できる" do
      owner = user_fixture(%{role: :owner})

      assert {:ok, updated} =
               Accounts.update_user_status(dev_scope(owner), owner, %{status: :suspended})

      assert updated.status == :suspended
    end

    test "⚠️ developer は他人の配下のユーザーを停止できない" do
      owner = user_fixture(%{role: :owner})
      other_dev = developer_scope_fixture()

      assert {:error, :unauthorized} =
               Accounts.update_user_status(other_dev, owner, %{status: :suspended})
    end

    test "admin は全クライアントのユーザーを停止できる" do
      owner = user_fixture(%{role: :owner})

      assert {:ok, _} =
               Accounts.update_user_status(admin_scope_fixture(), owner, %{status: :suspended})
    end

    test "⚠️ developer は他の developer を停止できない" do
      target = developer_fixture()
      scope = developer_scope_fixture()

      assert {:error, :unauthorized} =
               Platform.update_developer_status(scope, target, %{status: :suspended})
    end

    test "⚠️ admin は自分自身を停止できない" do
      # 止めると誰も入れなくなる
      scope = admin_scope_fixture()

      assert {:error, :cannot_suspend_self} =
               Platform.update_developer_status(scope, scope.developer, %{status: :suspended})
    end
  end

  describe "suspension_reason/1" do
    test "3 段のどこで止まっているか分かる" do
      user = user_fixture()
      assert Accounts.suspension_reason(user) == nil

      assert Accounts.suspension_reason(suspend_user(user)) == :user
    end

    test "⚠️ preload されていなければ raise する（黙って利用可にしない）" do
      user = user_fixture()

      assert_raise ArgumentError, ~r/preload/, fn ->
        Accounts.suspension_reason(%{user | client: %Ecto.Association.NotLoaded{}})
      end
    end
  end
end
