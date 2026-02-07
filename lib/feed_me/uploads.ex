defmodule FeedMe.Uploads do
  @moduledoc """
  Handles saving and deleting uploaded files (base64 data URLs → local files).
  """

  @upload_dir "priv/static/uploads"

  @doc """
  Saves a base64 data URL as a recipe photo file.

  Returns `{:ok, url_path}` where url_path is like `/uploads/recipes/{recipe_id}/{uuid}.jpg`.
  """
  def save_recipe_photo(base64_data_url, recipe_id) do
    with {:ok, binary, ext} <- decode_data_url(base64_data_url) do
      filename = "#{Ecto.UUID.generate()}.#{ext}"
      dir = Path.join([@upload_dir, "recipes", recipe_id])
      path = Path.join(dir, filename)

      File.mkdir_p!(dir)
      File.write!(path, binary)

      {:ok, "/uploads/recipes/#{recipe_id}/#{filename}"}
    end
  end

  @doc """
  Deletes a file at the given URL path (only `/uploads/` paths).
  """
  def delete_file("/uploads/" <> _ = url_path) do
    path = Path.join("priv/static", url_path)

    if File.exists?(path) do
      File.rm(path)
    else
      :ok
    end
  end

  def delete_file(_), do: :ok

  defp decode_data_url("data:" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [meta, encoded] ->
        ext = mime_to_ext(meta)
        {:ok, Base.decode64!(encoded), ext}

      _ ->
        {:error, :invalid_data_url}
    end
  end

  defp decode_data_url(_), do: {:error, :invalid_data_url}

  defp mime_to_ext(meta) do
    cond do
      String.contains?(meta, "image/png") -> "png"
      String.contains?(meta, "image/gif") -> "gif"
      String.contains?(meta, "image/webp") -> "webp"
      true -> "jpg"
    end
  end
end
