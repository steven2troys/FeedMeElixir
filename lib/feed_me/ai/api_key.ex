defmodule FeedMe.AI.ApiKey do
  @moduledoc """
  Schema for encrypted AI provider API keys (BYOK).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ai_api_keys" do
    field :provider, :string
    field :encrypted_key, :binary
    field :key_hint, :string
    field :is_valid, :boolean, default: true
    field :last_used_at, :utc_datetime

    # Virtual field for the raw key during creation
    field :api_key, :string, virtual: true

    belongs_to :household, FeedMe.Households.Household
    belongs_to :created_by, FeedMe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @providers ~w(openrouter anthropic openai)

  @doc false
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:provider, :api_key, :household_id, :created_by_id])
    |> validate_required([:provider, :api_key, :household_id])
    |> validate_inclusion(:provider, @providers)
    |> encrypt_key()
    |> set_key_hint()
    |> unique_constraint([:household_id, :provider])
  end

  defp encrypt_key(changeset) do
    case get_change(changeset, :api_key) do
      nil ->
        changeset

      key ->
        # Simple encryption using application secret
        # In production, use Cloak or Vault
        encrypted = encrypt(key)
        put_change(changeset, :encrypted_key, encrypted)
    end
  end

  defp set_key_hint(changeset) do
    case get_change(changeset, :api_key) do
      nil ->
        changeset

      key when is_binary(key) and byte_size(key) >= 4 ->
        hint = "..." <> String.slice(key, -4, 4)
        put_change(changeset, :key_hint, hint)

      _ ->
        changeset
    end
  end

  @doc """
  Decrypts and returns the API key.
  """
  def decrypt_key(%__MODULE__{encrypted_key: encrypted}) when is_binary(encrypted) do
    decrypt(encrypted)
  end

  def decrypt_key(_), do: nil

  # Simple XOR encryption with app secret - replace with Cloak in production
  defp encrypt(plaintext) do
    key = encryption_key()

    :crypto.exor(
      plaintext,
      String.duplicate(key, div(byte_size(plaintext), byte_size(key)) + 1)
      |> binary_part(0, byte_size(plaintext))
    )
  end

  defp decrypt(ciphertext) do
    # XOR is symmetric
    encrypt(ciphertext)
  end

  defp encryption_key do
    Application.get_env(:feed_me, :encryption_key) ||
      Base.decode64!(Application.get_env(:feed_me, FeedMeWeb.Endpoint)[:secret_key_base])
      |> binary_part(0, 32)
  end
end
