defmodule FeedMe.AI.Vision do
  @moduledoc """
  Image analysis capabilities for FeedMe.
  Uses vision-capable AI models to analyze food images.
  """

  alias FeedMe.AI
  alias FeedMe.AI.ApiKey

  @vision_models [
    "anthropic/claude-3.5-sonnet",
    "anthropic/claude-3-opus",
    "anthropic/claude-3-haiku",
    "openai/gpt-4-vision-preview",
    "openai/gpt-4o",
    "google/gemini-pro-vision"
  ]

  @doc """
  Analyzes a fridge or pantry image to identify food items.
  Returns a list of identified items with quantities.
  """
  def analyze_fridge(household_id, image_data, opts \\ []) do
    prompt = """
    Analyze this image of a refrigerator or pantry. List all visible food items you can identify.

    For each item, provide:
    - Name of the item
    - Estimated quantity (e.g., "2 bottles", "1/2 full", "3 pieces")
    - Approximate freshness if visible (good, needs to be used soon, expired)

    Format as a list with one item per line:
    Item Name | Quantity | Freshness

    Only list items you can clearly identify. Don't guess at unclear items.
    """

    analyze_image(household_id, image_data, prompt, opts)
  end

  @doc """
  Analyzes a dish image to estimate nutritional macros.
  """
  def analyze_dish_macros(household_id, image_data, opts \\ []) do
    prompt = """
    Analyze this image of a food dish and estimate its nutritional content.

    Provide:
    1. Description of the dish
    2. Estimated serving size
    3. Approximate macros:
       - Calories
       - Protein (grams)
       - Carbohydrates (grams)
       - Fat (grams)
    4. Key ingredients visible

    Be clear that these are estimates based on visual analysis.
    """

    analyze_image(household_id, image_data, prompt, opts)
  end

  @doc """
  Extracts recipe information from an image of a recipe card, book page, or screenshot.
  """
  def digitize_recipe(household_id, image_data, opts \\ []) do
    prompt = """
    Extract the recipe from this image. Provide the information in a structured format:

    TITLE: [Recipe name]

    SERVINGS: [Number]

    PREP TIME: [Minutes]

    COOK TIME: [Minutes]

    INGREDIENTS:
    - [Quantity] [Unit] [Ingredient name]
    - (one per line)

    INSTRUCTIONS:
    1. [First step]
    2. [Second step]
    (numbered steps)

    NOTES: [Any additional notes or tips visible]

    If any information is not visible or unclear, mark it as "Not specified".
    """

    analyze_image(household_id, image_data, prompt, opts)
  end

  @doc """
  General food image analysis with custom prompt.
  """
  def analyze_food(household_id, image_data, custom_prompt, opts \\ []) do
    analyze_image(household_id, image_data, custom_prompt, opts)
  end

  @doc """
  Identifies a single food item from an image (useful for barcode fallback).
  """
  def identify_food(household_id, image_data, opts \\ []) do
    prompt = """
    What food item is shown in this image? Provide:

    1. Name of the item
    2. Common category (Produce, Dairy, Meat, etc.)
    3. Typical unit of measurement for this item
    4. Any brand visible (or "Generic" if not visible)

    Be specific but concise.
    """

    analyze_image(household_id, image_data, prompt, opts)
  end

  # Private functions

  defp analyze_image(household_id, image_data, prompt, opts) do
    case AI.get_api_key(household_id) do
      nil ->
        {:error, :no_api_key}

      api_key ->
        decrypted_key = ApiKey.decrypt_key(api_key)
        model = Keyword.get(opts, :model, default_vision_model())

        messages = [
          %{
            role: :user,
            content: [
              %{type: "text", text: prompt},
              %{type: "image_url", image_url: %{url: image_data_url(image_data)}}
            ]
          }
        ]

        request_vision_analysis(decrypted_key, model, messages)
    end
  end

  defp request_vision_analysis(api_key, model, messages) do
    url = "https://openrouter.ai/api/v1/chat/completions"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"HTTP-Referer", "https://feedme.app"},
      {"X-Title", "FeedMe"}
    ]

    # Format messages for vision API
    formatted_messages =
      Enum.map(messages, fn msg ->
        content =
          if is_list(msg.content) do
            Enum.map(msg.content, fn
              %{type: "text", text: text} ->
                %{type: "text", text: text}

              %{type: "image_url", image_url: %{url: url}} ->
                %{type: "image_url", image_url: %{url: url}}
            end)
          else
            msg.content
          end

        %{role: to_string(msg.role), content: content}
      end)

    body = %{
      model: model,
      messages: formatted_messages,
      max_tokens: 2000
    }

    case Req.post(url, headers: headers, json: body, receive_timeout: 60_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        content = get_in(body, ["choices", Access.at(0), "message", "content"])
        {:ok, content}

      {:ok, %{status: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp image_data_url(data) when is_binary(data) do
    cond do
      String.starts_with?(data, "data:") ->
        # Already a data URL
        data

      String.starts_with?(data, "http") ->
        # Regular URL
        data

      true ->
        # Assume base64 encoded image
        mime_type = detect_mime_type(data)
        "data:#{mime_type};base64,#{data}"
    end
  end

  defp detect_mime_type(base64_data) do
    # Decode just enough to check the magic bytes
    case Base.decode64(base64_data, ignore: :whitespace) do
      {:ok, <<0x89, 0x50, 0x4E, 0x47, _rest::binary>>} -> "image/png"
      {:ok, <<0xFF, 0xD8, 0xFF, _rest::binary>>} -> "image/jpeg"
      {:ok, <<0x47, 0x49, 0x46, _rest::binary>>} -> "image/gif"
      {:ok, <<"RIFF", _::binary-size(4), "WEBP", _rest::binary>>} -> "image/webp"
      _ -> "image/jpeg"
    end
  end

  @doc """
  Returns the default vision model.
  """
  def default_vision_model do
    "anthropic/claude-3.5-sonnet"
  end

  @doc """
  Returns all supported vision models.
  """
  def vision_models, do: @vision_models

  @doc """
  Checks if a model supports vision.
  """
  def supports_vision?(model) do
    Enum.any?(@vision_models, fn vm ->
      String.starts_with?(model, vm) or model == vm
    end)
  end
end
