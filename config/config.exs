# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :feed_me, :scopes,
  user: [
    default: true,
    module: FeedMe.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: FeedMe.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :feed_me,
  ecto_repos: [FeedMe.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :feed_me, FeedMeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FeedMeWeb.ErrorHTML, json: FeedMeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FeedMe.PubSub,
  live_view: [signing_salt: "EAXESZSe"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :feed_me, FeedMe.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  feed_me: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  feed_me: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth for Google OAuth
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]}
  ]

# Google OAuth credentials (override in runtime.exs for production)
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

# OpenRouter API configuration
config :feed_me, :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY"),
  default_model: System.get_env("OPENROUTER_DEFAULT_MODEL", "anthropic/claude-3.5-sonnet")

# Encryption key for API keys (32 bytes for AES-256)
config :feed_me, :encryption_key, System.get_env("ENCRYPTION_KEY")

# Pantry Sync (AI-powered batch pantry updates from shopping lists)
config :feed_me, FeedMe.Pantry.Sync,
  debounce_ms: :timer.minutes(10),
  enabled: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
