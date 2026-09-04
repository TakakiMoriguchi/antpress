import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :antpress, AntPress.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5433,
  database: "antpress_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :antpress, AntPressWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hAuMkM2NL4uIBigwS0vEQGy5BMJPih8pwft1FIHY9D/5ZpDg2sTeAyn5fTh5ZG1s",
  server: false

# テストはネットワークに依存させない。常にローカルディスクを使い、
# 書き込み先はプロジェクト外の一時ディレクトリにしてリポジトリを汚さない。
# Supabase アダプタ自体は Req.Test をプラグで差し込んで検証する
# （→ test/antpress/storage/supabase_test.exs）。
config :antpress, :storage,
  adapter: AntPress.Storage.Local,
  root: Path.join(System.tmp_dir!(), "antpress-test-uploads"),
  url_prefix: "/uploads"

# In test we don't send emails
config :antpress, AntPress.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Cloak（developer の Anthropic API キーの暗号化）
# ⚠️ この鍵は開発専用。本番は runtime.exs が CLOAK_KEY 環境変数から読む。
#    Phoenix が dev.exs に secret_key_base を含めるのと同じ扱い。
config :antpress, AntPress.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("tdU4+aIRcQ2eR6hU29WO0l2pKOxjina79G9c19IN+7U=")}
  ]
