defmodule FeedMe.AI.OpenRouter do
  @moduledoc """
  HTTP client for OpenRouter API.
  """

  @base_url "https://openrouter.ai/api/v1"

  @doc """
  Lists available models from OpenRouter.
  Options:
  - :tools - filter for models that support tool use (default: false)
  - :vision - filter for models that support vision/images (default: false)
  """
  def list_models(api_key, opts \\ []) do
    require_tools = Keyword.get(opts, :tools, false)
    require_vision = Keyword.get(opts, :vision, false)

    case request(:get, "/models", api_key) do
      {:ok, %{"data" => models}} ->
        filtered = filter_models(models, require_tools, require_vision)
        {:ok, filtered}

      error ->
        error
    end
  end

  @doc """
  Lists models that support both tools and vision.
  """
  def list_capable_models(api_key) do
    list_models(api_key, tools: true, vision: true)
  end

  @doc """
  Sends a chat completion request.
  """
  def chat(api_key, messages, opts \\ []) do
    model = Keyword.get(opts, :model, "anthropic/claude-3.5-sonnet")
    tools = Keyword.get(opts, :tools, [])
    stream = Keyword.get(opts, :stream, false)

    body = %{
      model: model,
      messages: format_messages(messages),
      stream: stream
    }

    body = if tools != [], do: Map.put(body, :tools, tools), else: body

    case request(:post, "/chat/completions", api_key, body) do
      {:ok, response} -> {:ok, parse_response(response)}
      error -> error
    end
  end

  @doc """
  Sends a streaming chat completion request.
  Calls the callback function for each chunk.
  """
  def chat_stream(api_key, messages, callback, opts \\ []) do
    model = Keyword.get(opts, :model, "anthropic/claude-3.5-sonnet")
    tools = Keyword.get(opts, :tools, [])

    body = %{
      model: model,
      messages: format_messages(messages),
      stream: true
    }

    body = if tools != [], do: Map.put(body, :tools, tools), else: body

    stream_request("/chat/completions", api_key, body, callback)
  end

  # Private functions

  defp request(method, path, api_key, body \\ nil) do
    url = @base_url <> path

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"HTTP-Referer", "https://feedme.app"},
      {"X-Title", "FeedMe"}
    ]

    req_opts = [
      method: method,
      url: url,
      headers: headers,
      receive_timeout: 90_000,
      retry: :transient,
      max_retries: 2
    ]

    req_opts = if body, do: Keyword.put(req_opts, :json, body), else: req_opts

    case Req.request(req_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp stream_request(path, api_key, body, callback) do
    url = @base_url <> path

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"HTTP-Referer", "https://feedme.app"},
      {"X-Title", "FeedMe"}
    ]

    # Use Req's streaming capabilities
    case Req.post(url,
           headers: headers,
           json: body,
           receive_timeout: 120_000,
           into: fn {:data, data}, {req, resp} ->
             process_stream_chunk(data, callback)
             {:cont, {req, resp}}
           end
         ) do
      {:ok, _response} ->
        callback.({:done, nil})
        :ok

      {:error, reason} ->
        callback.({:error, reason})
        {:error, reason}
    end
  end

  defp process_stream_chunk(data, callback) do
    data
    |> String.split("\n")
    |> Enum.each(fn line ->
      case line do
        "data: [DONE]" ->
          :ok

        "data: " <> json_str ->
          case Jason.decode(json_str) do
            {:ok, parsed} ->
              delta = get_in(parsed, ["choices", Access.at(0), "delta"])

              if delta do
                callback.({:chunk, delta})
              end

            _ ->
              :ok
          end

        _ ->
          :ok
      end
    end)
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      base = %{role: to_string(msg.role), content: msg.content}

      base =
        case Map.get(msg, :tool_calls) do
          nil -> base
          [] -> base
          tool_calls -> Map.put(base, :tool_calls, tool_calls)
        end

      case Map.get(msg, :tool_call_id) do
        nil -> base
        "" -> base
        tool_call_id -> Map.put(base, :tool_call_id, tool_call_id)
      end
    end)
  end

  defp parse_response(%{"choices" => [choice | _]} = response) do
    message = choice["message"]

    %{
      content: message["content"],
      tool_calls: message["tool_calls"],
      finish_reason: choice["finish_reason"],
      usage: response["usage"],
      citations: response["citations"]
    }
  end

  defp parse_response(response), do: response

  defp filter_models(models, require_tools, require_vision) do
    models
    |> Enum.filter(fn model ->
      tools_ok = not require_tools or supports_tools?(model)
      vision_ok = not require_vision or supports_vision?(model)
      tools_ok and vision_ok
    end)
    |> Enum.map(fn model ->
      %{
        id: model["id"],
        name: model["name"] || model["id"],
        context_length: model["context_length"],
        pricing: model["pricing"],
        supports_tools: supports_tools?(model),
        supports_vision: supports_vision?(model),
        description: model["description"]
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp supports_tools?(model) do
    # Check OpenRouter's architecture field for tool support
    arch = model["architecture"] || %{}
    instruct_type = arch["instruct_type"]

    # Check supported_parameters for tool support
    supported = model["supported_parameters"] || []

    # Models with function calling support
    has_tool_param = "tools" in supported or "tool_choice" in supported

    # Known model families that support tools
    model_id = model["id"] || ""

    known_tool_models = [
      "anthropic/claude-3",
      "anthropic/claude-3.5",
      "openai/gpt-4",
      "openai/gpt-3.5-turbo",
      "google/gemini",
      "mistralai/mistral-large",
      "mistralai/mistral-medium",
      "cohere/command-r"
    ]

    known_support = Enum.any?(known_tool_models, &String.starts_with?(model_id, &1))

    has_tool_param or known_support or instruct_type == "tool_use"
  end

  defp supports_vision?(model) do
    # Check architecture modality for vision support
    arch = model["architecture"] || %{}
    modality = arch["modality"] || ""

    # Check if modality includes image input
    has_image_input =
      String.contains?(modality, "image") or
        String.contains?(modality, "multimodal")

    # Known vision models
    model_id = model["id"] || ""

    known_vision_models = [
      "anthropic/claude-3",
      "openai/gpt-4-vision",
      "openai/gpt-4o",
      "openai/gpt-4-turbo",
      "google/gemini-pro-vision",
      "google/gemini-1.5",
      "google/gemini-2"
    ]

    known_support = Enum.any?(known_vision_models, &String.starts_with?(model_id, &1))

    has_image_input or known_support
  end
end
