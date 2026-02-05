defmodule FeedMe.Repo.Migrations.AddTimezoneToHouseholds do
  use Ecto.Migration

  def change do
    alter table(:households) do
      add :timezone, :string, default: "America/Los_Angeles"
    end
  end
end
