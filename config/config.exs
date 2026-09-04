# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# phx.gen.auth を 2 系統（developer / user）実行しているため scope が 2 つある。
#
# ⚠️ 既定スコープ（default: true）は **client** にしている。
#    antpress のリソースは大半がクライアント配下（記事・カテゴリ・画像・
#    問い合わせ）で client_id でスコープするため。
#    developer_id でスコープするのは clients と api_keys だけなので、
#    そちらを生成するときは --no-scope で生成して手で書く。
config :antpress, :scopes,
  developer: [
    default: false,
    module: AntPress.Platform.Scope,
    assign_key: :current_developer,
    access_path: [:developer, :id],
    schema_key: :developer_id,
    schema_type: :binary_id,
    schema_table: :developers,
    test_data_fixture: AntPress.PlatformFixtures,
    test_setup_helper: :register_and_log_in_developer
  ],
  # クライアント配下のリソース用。AntPress.Accounts.Scope は client を
  # 必ず持つので（→ lib/antpress/accounts/scope.ex）、client.id で
  # スコープできる。
  client: [
    default: true,
    module: AntPress.Accounts.Scope,
    assign_key: :current_user,
    access_path: [:client, :id],
    schema_key: :client_id,
    schema_type: :binary_id,
    schema_table: :clients,
    test_data_fixture: AntPress.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :antpress,
  namespace: AntPress,
  ecto_repos: [AntPress.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :antpress, AntPressWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AntPressWeb.ErrorHTML, json: AntPressWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AntPress.PubSub,
  live_view: [signing_salt: "vcxRKiIV"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :antpress, AntPress.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  antpress: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  antpress: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
