defmodule FeedMe.Repo.Migrations.CreateConversationShares do
  use Ecto.Migration

  def change do
    create table(:conversation_shares, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:ai_conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_shares, [:conversation_id, :user_id])
    create index(:conversation_shares, [:user_id])
  end
end
