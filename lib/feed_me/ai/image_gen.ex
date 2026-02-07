defmodule FeedMe.AI.ImageGen do
  @moduledoc """
  AI image generation for recipe photos via OpenRouter.
  Uses google/gemini-2.5-flash-image (Nano Banana) which supports
  image output through the standard chat completions endpoint.
  """

  require Logger

  @base_url "https://openrouter.ai/api/v1"
  @model "google/gemini-2.5-flash-image"

  @doc """
  Generates a recipe photo using AI.

  Returns `{:ok, base64_data_url}` on success.
  The recipe should be preloaded with ingredients.
  """
  def generate_recipe_photo(api_key, recipe) do
    prompt = build_prompt(recipe)

    body = %{
      model: @model,
      messages: [
        %{role: "user", content: prompt}
      ],
      modalities: ["image", "text"]
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"HTTP-Referer", "https://feedme.app"},
      {"X-Title", "FeedMe"}
    ]

    case Req.post(@base_url <> "/chat/completions",
           headers: headers,
           json: body,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        extract_image(resp_body)

      {:ok, %{status: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("ImageGen API error #{status}: #{inspect(resp_body)}")
        {:error, "API error #{status}"}

      {:error, reason} ->
        Logger.error("ImageGen request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp build_prompt(recipe) do
    ingredient_names =
      case recipe.ingredients do
        ingredients when is_list(ingredients) and ingredients != [] ->
          names = Enum.map_join(ingredients, ", ", & &1.name)
          "Key ingredients: #{names}."

        _ ->
          ""
      end

    description =
      if recipe.description,
        do: "Description: #{recipe.description}.",
        else: ""

    """
    Generate a beautiful, appetizing food photography image of "#{recipe.title}".
    #{description}
    #{ingredient_names}
    Style: Professional food photography, natural lighting, shallow depth of field, \
    on a clean plate with subtle garnish. Top-down or 45-degree angle. \
    Warm, inviting colors. No text or watermarks.
    """
    |> String.trim()
  end

  # OpenRouter returns images in message.images array
  # Format: %{"images" => [%{"type" => "image_url", "image_url" => %{"url" => "data:..."}}]}
  defp extract_image(%{"choices" => [%{"message" => message} | _]}) do
    case message do
      %{"images" => [%{"image_url" => %{"url" => url}} | _]} ->
        {:ok, url}

      other ->
        Logger.error("ImageGen: no image in response message: #{inspect(Map.keys(other))}")
        {:error, :no_image_in_response}
    end
  end

  defp extract_image(other) do
    Logger.error("ImageGen: unexpected response format: #{inspect(Map.keys(other))}")
    {:error, :unexpected_response_format}
  end
end
