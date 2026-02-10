defmodule FeedMe.Repo.Migrations.AddAutomationTierToHouseholds do
  use Ecto.Migration

  def change do
    alter table(:households) do
      add :automation_tier, :string, null: false, default: "off"
    end
  end
end
