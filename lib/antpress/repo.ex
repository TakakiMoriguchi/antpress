defmodule AntPress.Repo do
  use Ecto.Repo,
    otp_app: :antpress,
    adapter: Ecto.Adapters.Postgres
end
