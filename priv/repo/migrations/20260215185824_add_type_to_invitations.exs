defmodule FeedMe.Repo.Migrations.AddTypeToInvitations do
  use Ecto.Migration

  def change do
    alter table(:invitations) do
      add :type, :string, null: false, default: "join_household"
    end
  end
end
