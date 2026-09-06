defmodule AntPressWeb.Router do
  use AntPressWeb, :router

  import AntPressWeb.UserAuth

  import AntPressWeb.DeveloperAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AntPressWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user_for_user
    plug :fetch_current_developer_for_developer
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AntPressWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", AntPressWeb do
  #   pipe_through :api
  # end

  # 開発時のメールプレビュー。マジックリンクログインの確認に使う
  # （→ docs/DECISIONS.md 3.5）。LiveDashboard は採用しない（薄く保つ方針）
  if Application.compile_env(:antpress, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", AntPressWeb do
    pipe_through [:browser, :require_authenticated_developer]

    live_session :require_authenticated_developer,
      on_mount: [{AntPressWeb.DeveloperAuth, :require_authenticated}] do
      live "/developers/settings", DeveloperLive.Settings, :edit
      # パスワード変更は別ページ。ここだけ再認証（sudo モード）が要る
      live "/developers/settings/password", DeveloperLive.Password, :edit

      # クライアント管理（→ docs/SCREENS.md D3〜D5）
      # admin と developer が共用する。スコープは Platform 側で強制する
      live "/clients", ClientLive.Index, :index
      live "/clients/new", ClientLive.Form, :new
      live "/clients/:id", ClientLive.Show, :show
      live "/clients/:id/edit", ClientLive.Form, :edit
    end

    post "/developers/update-password", DeveloperSessionController, :update_password
  end

  scope "/", AntPressWeb do
    pipe_through [:browser]

    live_session :current_developer,
      on_mount: [{AntPressWeb.DeveloperAuth, :mount_current_developer}] do
      live "/developers/log-in", DeveloperLive.Login, :new
      live "/developers/log-in/:token", DeveloperLive.Confirmation, :new
    end

    post "/developers/log-in", DeveloperSessionController, :create
    delete "/developers/log-out", DeveloperSessionController, :delete
  end

  ## Authentication routes

  scope "/", AntPressWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{AntPressWeb.UserAuth, :require_authenticated}] do
      live "/client/settings", UserLive.Settings, :edit
      # パスワード変更は別ページ。ここだけ再認証（sudo モード）が要る
      # （→ lib/antpress_web/live/user_live/password.ex）
      live "/client/settings/password", UserLive.Password, :edit

      # 記事（→ docs/SCREENS.md C3 / C4）。ログイン後の着地点
      live "/client/articles", ArticleLive.Index, :index
      live "/client/articles/new", ArticleLive.Form, :new
      live "/client/articles/:id/edit", ArticleLive.Form, :edit

      # カテゴリ管理（→ docs/SCREENS.md C5）
      live "/client/categories", CategoryLive.Index, :index
      live "/client/categories/new", CategoryLive.Form, :new
      live "/client/categories/:id", CategoryLive.Show, :show
      live "/client/categories/:id/edit", CategoryLive.Form, :edit

      # 画像管理（→ docs/SCREENS.md C6）
      # アップロード・alt 設定・削除を 1 画面で行うので 1 ルートだけ
      live "/client/images", ImageLive.Index, :index
    end

    post "/client/update-password", UserSessionController, :update_password

    # 記事本文への画像挿入（Toast UI の addImageBlobHook から呼ばれる）。
    # LiveView ではなくコントローラなのは、ファイルが JS の握る Blob として
    # 来るため（→ lib/antpress_web/controllers/editor_image_controller.ex）
    post "/client/editor/images", EditorImageController, :create
  end

  scope "/", AntPressWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{AntPressWeb.UserAuth, :mount_current_user}] do
      # セルフサインアップは提供しない。オーナーは developer が発行し、
      # スタッフはオーナーが発行する（→ docs/DECISIONS.md 1.3 / 3.5）
      live "/client/log-in", UserLive.Login, :new
      live "/client/log-in/:token", UserLive.Confirmation, :new
    end

    post "/client/log-in", UserSessionController, :create
    delete "/client/log-out", UserSessionController, :delete
  end
end
