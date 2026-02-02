defmodule FeedMe.Suppliers.HouseholdSupplier do
  @moduledoc """
  Schema for household-supplier connections.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "household_suppliers" do
    field :is_default, :boolean, default: false
    field :credentials, :binary
    field :settings, :map, default: %{}
    field :last_synced_at, :utc_datetime

    # Virtual field for decrypted credentials
    field :api_credentials, :map, virtual: true

    belongs_to :household, FeedMe.Households.Household
    belongs_to :supplier, FeedMe.Suppliers.Supplier
    belongs_to :configured_by, FeedMe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(household_supplier, attrs) do
    household_supplier
    |> cast(attrs, [
      :is_default,
      :api_credentials,
      :settings,
      :last_synced_at,
      :household_id,
      :supplier_id,
      :configured_by_id
    ])
    |> validate_required([:household_id, :supplier_id])
    |> encrypt_credentials()
    |> unique_constraint([:household_id, :supplier_id])
    |> foreign_key_constraint(:household_id)
    |> foreign_key_constraint(:supplier_id)
  end

  defp encrypt_credentials(changeset) do
    case get_change(changeset, :api_credentials) do
      nil ->
        changeset

      credentials when is_map(credentials) ->
        encrypted = encrypt(Jason.encode!(credentials))
        put_change(changeset, :credentials, encrypted)

      _ ->
        changeset
    end
  end

  @doc """
  Decrypts and returns the API credentials.
  """
  def decrypt_credentials(%__MODULE__{credentials: nil}), do: nil

  def decrypt_credentials(%__MODULE__{credentials: encrypted}) when is_binary(encrypted) do
    case decrypt(encrypted) do
      nil -> nil
      json -> Jason.decode!(json)
    end
  end

  # Simple XOR encryption - replace with Cloak in production
  defp encrypt(plaintext) do
    key = encryption_key()
    :crypto.exor(plaintext, String.duplicate(key, div(byte_size(plaintext), byte_size(key)) + 1) |> binary_part(0, byte_size(plaintext)))
  end

  defp decrypt(ciphertext) do
    encrypt(ciphertext)
  end

  defp encryption_key do
    Application.get_env(:feed_me, :encryption_key) ||
      Base.decode64!(Application.get_env(:feed_me, FeedMeWeb.Endpoint)[:secret_key_base])
      |> binary_part(0, 32)
  end
end
