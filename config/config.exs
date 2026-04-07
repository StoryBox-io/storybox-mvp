# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :storybox,
  ecto_repos: [Storybox.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :storybox, StoryboxWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: StoryboxWeb.ErrorHTML, json: StoryboxWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Storybox.PubSub,
  live_view: [signing_salt: "rIuOyS09"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :storybox, Storybox.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# ExAws — defaults read from env vars at runtime (see runtime.exs for prod).
# In dev/test these are overridden by individual env vars if present.
config :ex_aws,
  access_key_id: [{:system, "MINIO_ACCESS_KEY"}, :instance_role],
  secret_access_key: [{:system, "MINIO_SECRET_KEY"}, :instance_role],
  json_codec: Jason

config :ex_aws, :s3,
  scheme: "http://",
  host: "localhost",
  port: 9000

# Ash formatter plugin
config :ash, :formatter, [
  extensions: [Ash.Formatter]
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
