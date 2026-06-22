defmodule StoryboxWeb.Router do
  use StoryboxWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StoryboxWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_api_auth do
    plug StoryboxWeb.Plugs.ApiAuth
  end

  scope "/", StoryboxWeb do
    pipe_through :browser

    sign_in_route(register_path: "/register", reset_path: "/reset", auth_routes_prefix: "/auth")
    sign_out_route(AuthController)
    auth_routes(AuthController, Storybox.Accounts.User)
    reset_route(auth_routes_prefix: "/auth")

    live_session :authenticated,
      on_mount: AshAuthentication.Phoenix.LiveSession do
      live "/", StoryListLive
      live "/stories/:story_id", StoryOverviewLive
    end
  end

  scope "/api", StoryboxWeb do
    pipe_through :api

    post "/auth/token", ApiController, :token
  end

  scope "/api", StoryboxWeb do
    pipe_through [:api, :require_api_auth]

    get "/stories/:story_id/ping", ApiController, :ping
    get "/stories/:story_id/views/synopsis", ApiController, :synopsis_view
    get "/stories/:story_id/views/script", ApiController, :script_view
    post "/stories/:story_id/scenes/:id/versions", ApiController, :create_scene_version
    get "/stories/:story_id/tasks", ApiController, :list_tasks
    post "/stories/:story_id/tasks/:id/in_progress", ApiController, :mark_task_in_progress
    post "/stories/:story_id/tasks/:id/complete", ApiController, :mark_task_complete
    post "/stories/:story_id/views/synopsis/cut", ApiController, :cut_synopsis_vv
    post "/stories/:story_id/views/treatment/cut", ApiController, :cut_treatment_vv

    post "/stories/:story_id/sequences/:seq_id/views/sequence/cut",
         ApiController,
         :cut_sequence_vv

    post "/stories/:story_id/scenes/:scene_id/views/script/cut", ApiController, :cut_script_vv
    post "/stories/:story_id/views/story_script/cut", ApiController, :cut_story_script_vv
    post "/stories/:story_id/sequences/:seq_id/weights", ApiController, :set_sequence_weights

    post "/stories/:story_id/sequences/:seq_slug/pieces",
         ApiController,
         :create_sequence_piece

    post "/stories/:story_id/scenes/:scene_id/weights", ApiController, :set_script_piece_weights

    get "/stories/:story_id/characters", ApiController, :list_characters
    get "/stories/:story_id/characters/:char_id", ApiController, :character_detail
    post "/stories/:story_id/characters/:char_id/pieces", ApiController, :create_character_piece
    get "/stories/:story_id/world", ApiController, :world_detail
    post "/stories/:story_id/world/pieces", ApiController, :create_world_piece
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:storybox, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: StoryboxWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
