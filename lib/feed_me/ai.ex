defmodule FeedMe.AI do
  @moduledoc """
  The AI context manages conversations, API keys, and AI interactions.
  """

  import Ecto.Query, warn: false
  alias FeedMe.AI.{ApiKey, Conversation, Message, OpenRouter, Tools}
  alias FeedMe.Repo

  # =============================================================================
  # API Keys
  # =============================================================================

  @doc """
  Gets the API key for a provider in a household.
  """
  def get_api_key(household_id, provider \\ "openrouter") do
    ApiKey
    |> where([k], k.household_id == ^household_id and k.provider == ^provider)
    |> Repo.one()
  end

  @doc """
  Creates or updates an API key for a household.
  """
  def set_api_key(household_id, provider, api_key, user) do
    case get_api_key(household_id, provider) do
      nil ->
        %ApiKey{}
        |> ApiKey.changeset(%{
          household_id: household_id,
          provider: provider,
          api_key: api_key,
          created_by_id: user.id
        })
        |> Repo.insert()

      existing ->
        existing
        |> ApiKey.changeset(%{api_key: api_key})
        |> Repo.update()
    end
  end

  @doc """
  Deletes an API key.
  """
  def delete_api_key(%ApiKey{} = api_key) do
    Repo.delete(api_key)
  end

  @doc """
  Validates an API key by making a test request.
  """
  def validate_api_key(api_key_string, provider \\ "openrouter") do
    case provider do
      "openrouter" ->
        case OpenRouter.list_models(api_key_string) do
          {:ok, _} -> :valid
          {:error, :invalid_api_key} -> :invalid
          {:error, _} -> :error
        end

      _ ->
        :unsupported
    end
  end

  @doc """
  Marks an API key as invalid.
  """
  def mark_key_invalid(%ApiKey{} = api_key) do
    api_key
    |> Ecto.Changeset.change(%{is_valid: false})
    |> Repo.update()
  end

  @doc """
  Updates the last_used_at timestamp.
  """
  def touch_api_key(%ApiKey{} = api_key) do
    api_key
    |> Ecto.Changeset.change(%{last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  # =============================================================================
  # Conversations
  # =============================================================================

  @doc """
  Lists conversations for a household.
  """
  def list_conversations(household_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Conversation
    |> where([c], c.household_id == ^household_id)
    |> where([c], c.status == :active)
    |> order_by([c], desc: c.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a conversation by ID.
  """
  def get_conversation(id) do
    Conversation
    |> Repo.get(id)
    |> Repo.preload(:messages)
  end

  @doc """
  Gets a conversation ensuring it belongs to the household.
  """
  def get_conversation(id, household_id) do
    Conversation
    |> where([c], c.id == ^id and c.household_id == ^household_id)
    |> preload(:messages)
    |> Repo.one()
  end

  @doc """
  Creates a new conversation.

  If no model is specified, uses the household's selected model.
  """
  def create_conversation(household_id, user, opts \\ []) do
    # Get the household's selected model if not provided
    model =
      case Keyword.get(opts, :model) do
        nil ->
          household = FeedMe.Households.get_household(household_id)
          household && household.selected_model

        model ->
          model
      end

    attrs = %{
      household_id: household_id,
      started_by_id: user.id,
      model: model,
      title: Keyword.get(opts, :title)
    }

    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conversation.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Archives a conversation.
  """
  def archive_conversation(%Conversation{} = conversation) do
    update_conversation(conversation, %{status: :archived})
  end

  @doc """
  Deletes a conversation and all its messages.
  """
  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  # =============================================================================
  # Messages
  # =============================================================================

  @doc """
  Lists messages for a conversation.
  """
  def list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a message in a conversation.
  """
  def create_message(conversation_id, attrs) do
    %Message{}
    |> Message.changeset(Map.put(attrs, :conversation_id, conversation_id))
    |> Repo.insert()
  end

  # =============================================================================
  # Chat
  # =============================================================================

  @doc """
  Sends a message and gets an AI response.

  Options:
  - :stream - whether to stream the response (default: false)
  - :callback - function to call for streaming chunks
  """
  def chat(conversation, user_message, context, opts \\ []) do
    household_id = conversation.household_id

    # Get API key
    case get_api_key(household_id) do
      nil ->
        {:error, :no_api_key}

      api_key ->
        decrypted_key = ApiKey.decrypt_key(api_key)

        # Get the household's selected model
        household = FeedMe.Households.get_household(household_id)
        model = household && household.selected_model || default_model()

        # Save user message
        {:ok, _user_msg} =
          create_message(conversation.id, %{
            role: :user,
            content: user_message
          })

        # Build message history
        messages = build_messages(conversation, user_message)

        # Add tools
        tools = Tools.definitions()

        # Make API request
        case do_chat(decrypted_key, messages, tools, context, conversation, model, opts) do
          {:ok, response} ->
            touch_api_key(api_key)
            {:ok, response}

          {:error, :invalid_api_key} ->
            mark_key_invalid(api_key)
            {:error, :invalid_api_key}

          error ->
            error
        end
    end
  end

  defp do_chat(api_key, messages, tools, context, conversation, model, opts) do
    stream = Keyword.get(opts, :stream, false)
    callback = Keyword.get(opts, :callback)

    if stream && callback do
      do_streaming_chat(api_key, messages, tools, context, conversation, model, callback)
    else
      do_sync_chat(api_key, messages, tools, context, conversation, model)
    end
  end

  defp do_sync_chat(api_key, messages, tools, context, conversation, model) do
    case OpenRouter.chat(api_key, messages, model: model, tools: tools) do
      {:ok, response} ->
        # Handle tool calls if present
        if response.tool_calls do
          handle_tool_calls(api_key, messages, tools, response, context, conversation, model)
        else
          # Save assistant message
          {:ok, assistant_msg} =
            create_message(conversation.id, %{
              role: :assistant,
              content: response.content,
              metadata: %{usage: response.usage}
            })

          # Update conversation title if first message
          maybe_update_title(conversation, messages)

          {:ok, assistant_msg}
        end

      error ->
        error
    end
  end

  defp do_streaming_chat(api_key, messages, tools, _context, conversation, model, callback) do
    accumulated_content = Agent.start_link(fn -> "" end)
    {:ok, acc_pid} = accumulated_content

    stream_callback = fn
      {:chunk, %{"content" => content}} when is_binary(content) ->
        Agent.update(acc_pid, fn acc -> acc <> content end)
        callback.({:chunk, content})

      {:chunk, %{"tool_calls" => tool_calls}} ->
        callback.({:tool_calls, tool_calls})

      {:done, _} ->
        final_content = Agent.get(acc_pid, & &1)
        Agent.stop(acc_pid)

        if final_content != "" do
          {:ok, _} =
            create_message(conversation.id, %{
              role: :assistant,
              content: final_content
            })
        end

        callback.({:done, final_content})

      {:error, reason} ->
        Agent.stop(acc_pid)
        callback.({:error, reason})
    end

    OpenRouter.chat_stream(api_key, messages, stream_callback, model: model, tools: tools)

    # Handle any tool calls that came through
    # (Tool calls in streaming are more complex, simplified here)
    maybe_update_title(conversation, messages)

    :ok
  end

  defp handle_tool_calls(api_key, messages, tools, response, context, conversation, model) do
    # Save assistant message with tool calls
    {:ok, _} =
      create_message(conversation.id, %{
        role: :assistant,
        content: response.content,
        tool_calls: response.tool_calls
      })

    # Execute each tool call
    tool_results =
      Enum.map(response.tool_calls, fn tool_call ->
        function = tool_call["function"]
        tool_name = function["name"]
        args = Jason.decode!(function["arguments"])

        result =
          case Tools.execute(tool_name, args, context) do
            {:ok, result} -> result
            {:error, error} -> "Error: #{error}"
          end

        # Save tool result message
        {:ok, _} =
          create_message(conversation.id, %{
            role: :tool,
            content: result,
            tool_call_id: tool_call["id"]
          })

        %{
          role: "tool",
          content: result,
          tool_call_id: tool_call["id"]
        }
      end)

    # Continue conversation with tool results
    updated_messages =
      messages ++
        [
          %{
            role: :assistant,
            content: response.content,
            tool_calls: response.tool_calls
          }
          | tool_results
        ]

    # Make another request to get final response
    case OpenRouter.chat(api_key, updated_messages, model: model, tools: tools) do
      {:ok, final_response} ->
        {:ok, assistant_msg} =
          create_message(conversation.id, %{
            role: :assistant,
            content: final_response.content,
            metadata: %{usage: final_response.usage}
          })

        {:ok, assistant_msg}

      error ->
        error
    end
  end

  defp build_messages(conversation, new_message) do
    # Get system prompt
    system = [%{role: :system, content: system_prompt()}]

    # Get conversation history
    # Exclude tool messages and tool_calls to avoid cross-provider ID mismatches
    history =
      conversation
      |> Repo.preload(:messages)
      |> Map.get(:messages, [])
      |> Enum.reject(fn msg -> msg.role == :tool end)
      |> Enum.map(fn msg ->
        %{
          role: msg.role,
          content: msg.content
        }
      end)

    # Add new user message
    system ++ history ++ [%{role: :user, content: new_message}]
  end

  defp system_prompt do
    """
    You are a helpful AI assistant for FeedMe, a household management app focused on grocery shopping, pantry inventory, and meal planning.

    Your capabilities include:
    - Managing the household's pantry inventory (adding items, checking stock)
    - Managing shopping lists (adding items to buy)
    - Searching and suggesting recipes
    - Understanding the household's taste profile (dietary restrictions, allergies, preferences)
    - Helping plan meals based on what's available

    Guidelines:
    - Be concise and helpful
    - Use the available tools to actually perform actions, don't just describe what you would do
    - When adding items, confirm what you've done
    - Consider dietary restrictions and allergies when suggesting recipes
    - If you're unsure about something, ask for clarification

    You have access to tools that let you interact with the household's data. Use them proactively to help the user.
    """
  end

  defp maybe_update_title(conversation, messages) do
    # Only update title if this is a new conversation (2 messages: system + first user)
    if conversation.title == nil and length(messages) <= 3 do
      # Get the first user message
      user_msg = Enum.find(messages, fn m -> m.role == :user end)

      if user_msg do
        # Generate a short title from the message
        title =
          user_msg.content
          |> String.slice(0, 50)
          |> String.trim()

        title = if String.length(user_msg.content) > 50, do: title <> "...", else: title
        update_conversation(conversation, %{title: title})
      end
    end
  end

  # =============================================================================
  # Models
  # =============================================================================

  @doc """
  Lists available models.
  """
  def list_models(household_id, opts \\ []) do
    case get_api_key(household_id) do
      nil ->
        {:error, :no_api_key}

      api_key ->
        decrypted_key = ApiKey.decrypt_key(api_key)
        OpenRouter.list_models(decrypted_key, opts)
    end
  end

  @doc """
  Lists models that support both tools and vision.
  """
  def list_capable_models(household_id) do
    list_models(household_id, tools: true, vision: true)
  end

  @doc """
  Returns the default model.
  """
  def default_model, do: "anthropic/claude-3.5-sonnet"

  @doc """
  Returns recommended models for different use cases.
  """
  def recommended_models do
    [
      %{id: "anthropic/claude-3.5-sonnet", name: "Claude 3.5 Sonnet", description: "Best balance of speed and capability"},
      %{id: "anthropic/claude-3-opus", name: "Claude 3 Opus", description: "Most capable, slower"},
      %{id: "openai/gpt-4-turbo", name: "GPT-4 Turbo", description: "Fast and capable"},
      %{id: "openai/gpt-4o", name: "GPT-4o", description: "Optimized for speed"},
      %{id: "google/gemini-pro-1.5", name: "Gemini Pro 1.5", description: "Large context window"}
    ]
  end
end
