defmodule FeedMe.Repo.Migrations.CreateAiTables do
  use Ecto.Migration

  def change do
    # API keys for BYOK (Bring Your Own Key)
    create table(:ai_api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :encrypted_key, :binary, null: false
      add :key_hint, :string  # Last 4 chars for display
      add :is_valid, :boolean, default: true
      add :last_used_at, :utc_datetime
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_api_keys, [:household_id, :provider])
    create index(:ai_api_keys, [:household_id])

    # Conversations
    create table(:ai_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :model, :string
      add :status, :string, default: "active"
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all), null: false
      add :started_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:ai_conversations, [:household_id])
    create index(:ai_conversations, [:household_id, :inserted_at])

    # Messages
    create table(:ai_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false  # user, assistant, system, tool
      add :content, :text
      add :tool_calls, :map  # JSON for tool calls
      add :tool_call_id, :string  # For tool responses
      add :metadata, :map  # tokens, model, etc.
      add :conversation_id, references(:ai_conversations, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ai_messages, [:conversation_id])
    create index(:ai_messages, [:conversation_id, :inserted_at])
  end
end
