import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :feed_me, FeedMe.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "feed_me_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :feed_me, FeedMeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "1qtskKQ+hxMn+v7UFheQ8i54x53VvMhuODCnoV6sEioOhQC6pP4oTsgONaiXeILT",
  server: false

# In test we don't send emails
config :feed_me, FeedMe.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Disable Pantry Sync in tests (start manually when needed)
config :feed_me, FeedMe.Pantry.Sync,
  debounce_ms: 0,
  enabled: false

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

# Google OAuth credentials (use env vars if available, otherwise test defaults)
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID") || "test-client-id",
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET") || "test-client-secret"

# OpenRouter API configuration
config :feed_me, :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY"),
  default_model: "anthropic/claude-3.5-sonnet"

# Encryption key for API keys
config :feed_me,
       :encryption_key,
       System.get_env("ENCRYPTION_KEY") || "test-encryption-key-32bytes!!"
