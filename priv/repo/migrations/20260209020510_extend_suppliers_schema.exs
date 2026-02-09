defmodule FeedMe.Repo.Migrations.ExtendSuppliersSchema do
  use Ecto.Migration

  def change do
    alter table(:suppliers) do
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all)
      add :supplier_type, :string
      add :website_url, :string
      add :deep_link_search_template, :string
      add :address, :string
      add :notes, :text
      add :supports_pickup, :boolean, default: false
    end

    create index(:suppliers, [:household_id])
  end
end
