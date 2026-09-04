# antpress の初期データ投入
#
#     mix run priv/repo/seeds.exs
#
# antpress は**セルフサインアップを一切行わない**（→ docs/DECISIONS.md 1.3）。
# 最初の admin アカウントはこの seed でのみ作成する。
# 以降、developer は admin が発行し、client のユーザーは developer が発行する。
#
# ## 環境変数
#
#   ADMIN_EMAIL     admin のメールアドレス（既定: admin@antpress.local）
#   ADMIN_NAME      屋号・氏名（既定: 運営者）
#                   管理画面のナビに表示される。role: admin には別途
#                   「運営」バッジが付くので、ここには実名や屋号を入れる
#   ADMIN_PASSWORD  指定するとパスワードを設定し、確認済みにする。
#                   省略時はマジックリンクでログインする（開発では /dev/mailbox で確認）

alias AntPress.Platform
alias AntPress.Platform.Developer
alias AntPress.Repo

email = System.get_env("ADMIN_EMAIL") || "admin@antpress.local"
name = System.get_env("ADMIN_NAME") || "運営者"
password = System.get_env("ADMIN_PASSWORD")

admin =
  case Platform.get_developer_by_email(email) do
    nil ->
      {:ok, admin} = Platform.create_developer(%{email: email, name: name, role: :admin})
      IO.puts("admin を作成しました: #{admin.email}")
      admin

    existing ->
      IO.puts("admin は既に存在します: #{existing.email}")
      existing
  end

if password do
  # ⚠️ パスワードを設定するなら confirmed_at も必ず入れる。
  #    「未確認かつパスワード設定済み」はマジックリンクログインが raise する状態
  #    （credential pre-stuffing 対策。mix help phx.gen.auth 参照）。
  admin
  |> Developer.password_changeset(%{password: password})
  |> Developer.confirm_changeset()
  |> Repo.update!()

  IO.puts("パスワードを設定し、確認済みにしました")
else
  IO.puts("パスワード未設定。マジックリンクでログインしてください（開発: /dev/mailbox）")
end
