defmodule FeedMeWeb.Router do
  use FeedMeWeb, :router

  import FeedMeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FeedMeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :nav_context do
    plug FeedMeWeb.Plugs.NavContext
  end

  scope "/", FeedMeWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", FeedMeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:feed_me, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FeedMeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  # Google OAuth routes
  scope "/auth", FeedMeWeb do
    pipe_through [:browser]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", FeedMeWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", FeedMeWeb do
    pipe_through [:browser, :require_authenticated_user, :nav_context]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email

    # Household list routes (no sidebar)
    live "/households", HouseholdLive.Index, :index
    live "/households/new", HouseholdLive.Index, :new

    # Household-scoped routes with sidebar layout
    live_session :household,
      on_mount: [{FeedMeWeb.LiveAuth, :default}, {FeedMeWeb.HouseholdHooks, :default}],
      layout: {FeedMeWeb.Layouts, :household} do
      live "/households/:id", HouseholdLive.Show, :show
      live "/households/:id/members", HouseholdLive.Members, :index
      live "/households/:id/members/:member_id/edit", HouseholdLive.Members, :edit_member
      live "/households/:id/invite", HouseholdLive.Members, :invite

      # Pantry routes
      live "/households/:household_id/pantry", PantryLive.Index, :index
      live "/households/:household_id/pantry/:id", PantryLive.Show, :show
      live "/households/:household_id/pantry/categories", PantryLive.Categories, :index

      # Shopping List routes
      live "/households/:household_id/shopping", ShoppingLive.Index, :index
      live "/households/:household_id/shopping/new", ShoppingLive.Index, :new
      live "/households/:household_id/shopping/:id", ShoppingLive.Show, :show
      live "/households/:household_id/shopping/:id/edit", ShoppingLive.Show, :edit
      live "/households/:household_id/shopping/:id/share", ShoppingLive.Show, :share

      # Recipe routes
      live "/households/:household_id/recipes", RecipeLive.Index, :index
      live "/households/:household_id/recipes/new", RecipeLive.Index, :new
      live "/households/:household_id/recipes/:id", RecipeLive.Show, :show
      live "/households/:household_id/recipes/:id/edit", RecipeLive.Show, :edit
      live "/households/:household_id/recipes/:id/cook", RecipeLive.Show, :cook

      # AI Chat routes
      live "/households/:household_id/chat", ChatLive.Index, :index
      live "/households/:household_id/chat/:id", ChatLive.Show, :show
      live "/households/:household_id/chat/:id/share", ChatLive.Show, :share

      # Settings routes
      live "/households/:household_id/settings", SettingsLive.Index, :index
      live "/households/:household_id/settings/households", SettingsLive.Households, :index
      live "/households/:household_id/settings/households/new", SettingsLive.Households, :new
      live "/households/:household_id/settings/api-key", SettingsLive.ApiKey, :edit
    end

    # Invitation acceptance
    live "/invitations/:token", InvitationLive.Accept, :accept
  end

  scope "/", FeedMeWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
