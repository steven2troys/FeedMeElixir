defmodule FeedMe.Repo.Migrations.AddGoogleOauthToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_id, :string
      add :name, :string
      add :avatar_url, :string
    end

    create unique_index(:users, [:google_id])
  end
end
