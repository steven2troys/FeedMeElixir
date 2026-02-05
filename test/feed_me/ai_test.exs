defmodule FeedMe.AITest do
  use FeedMe.DataCase

  alias FeedMe.AI
  alias FeedMe.AI.{ApiKey, Conversation, Message}
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures

  describe "api_keys" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "get_api_key/2 returns nil when no key exists", %{household: household} do
      assert AI.get_api_key(household.id) == nil
    end

    test "set_api_key/4 creates a new key", %{household: household, user: user} do
      {:ok, api_key} = AI.set_api_key(household.id, "openrouter", "sk-test-key-1234", user)

      assert api_key.provider == "openrouter"
      assert api_key.key_hint == "...1234"
      assert api_key.is_valid == true
      assert api_key.household_id == household.id
    end

    test "set_api_key/4 updates existing key", %{household: household, user: user} do
      {:ok, _} = AI.set_api_key(household.id, "openrouter", "sk-old-key-1111", user)
      {:ok, updated} = AI.set_api_key(household.id, "openrouter", "sk-new-key-2222", user)

      assert updated.key_hint == "...2222"

      # Should only be one key
      assert AI.get_api_key(household.id).id == updated.id
    end

    test "delete_api_key/1 removes the key", %{household: household, user: user} do
      {:ok, api_key} = AI.set_api_key(household.id, "openrouter", "sk-test-key", user)
      {:ok, _} = AI.delete_api_key(api_key)

      assert AI.get_api_key(household.id) == nil
    end

    test "mark_key_invalid/1 marks key as invalid", %{household: household, user: user} do
      {:ok, api_key} = AI.set_api_key(household.id, "openrouter", "sk-test-key", user)
      assert api_key.is_valid == true

      {:ok, marked} = AI.mark_key_invalid(api_key)
      assert marked.is_valid == false
    end

    test "touch_api_key/1 updates last_used_at", %{household: household, user: user} do
      {:ok, api_key} = AI.set_api_key(household.id, "openrouter", "sk-test-key", user)
      assert api_key.last_used_at == nil

      {:ok, touched} = AI.touch_api_key(api_key)
      assert touched.last_used_at != nil
    end

    test "decrypt_key/1 returns the original key", %{household: household, user: user} do
      original_key = "sk-test-key-1234"
      {:ok, api_key} = AI.set_api_key(household.id, "openrouter", original_key, user)

      # Reload from database to get encrypted version
      reloaded = AI.get_api_key(household.id)
      decrypted = ApiKey.decrypt_key(reloaded)

      assert decrypted == original_key
    end
  end

  describe "conversations" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "create_conversation/3 creates a new conversation", %{household: household, user: user} do
      {:ok, conversation} = AI.create_conversation(household.id, user)

      assert conversation.household_id == household.id
      assert conversation.started_by_id == user.id
      assert conversation.status == :active
    end

    test "create_conversation/3 with title", %{household: household, user: user} do
      {:ok, conversation} = AI.create_conversation(household.id, user, title: "Test Chat")

      assert conversation.title == "Test Chat"
    end

    test "list_conversations/1 returns conversations for household", %{
      household: household,
      user: user
    } do
      {:ok, conv1} = AI.create_conversation(household.id, user, title: "First")
      {:ok, _conv2} = AI.create_conversation(household.id, user, title: "Second")

      conversations = AI.list_conversations(household.id)
      assert length(conversations) == 2
    end

    test "list_conversations/1 excludes archived conversations", %{
      household: household,
      user: user
    } do
      {:ok, conv1} = AI.create_conversation(household.id, user, title: "Active")
      {:ok, conv2} = AI.create_conversation(household.id, user, title: "Archived")
      AI.archive_conversation(conv2)

      conversations = AI.list_conversations(household.id)
      assert length(conversations) == 1
      assert hd(conversations).id == conv1.id
    end

    test "get_conversation/2 returns conversation with messages", %{
      household: household,
      user: user
    } do
      {:ok, conversation} = AI.create_conversation(household.id, user)
      {:ok, _msg} = AI.create_message(conversation.id, %{role: :user, content: "Hello"})

      fetched = AI.get_conversation(conversation.id, household.id)
      assert fetched.id == conversation.id
      assert length(fetched.messages) == 1
    end

    test "get_conversation/2 returns nil for wrong household", %{household: household, user: user} do
      {:ok, conversation} = AI.create_conversation(household.id, user)

      other_user = AccountsFixtures.user_fixture()
      other_household = HouseholdsFixtures.household_fixture(%{}, other_user)

      assert AI.get_conversation(conversation.id, other_household.id) == nil
    end

    test "archive_conversation/1 sets status to archived", %{household: household, user: user} do
      {:ok, conversation} = AI.create_conversation(household.id, user)
      assert conversation.status == :active

      {:ok, archived} = AI.archive_conversation(conversation)
      assert archived.status == :archived
    end

    test "delete_conversation/1 removes conversation and messages", %{
      household: household,
      user: user
    } do
      {:ok, conversation} = AI.create_conversation(household.id, user)
      {:ok, _msg} = AI.create_message(conversation.id, %{role: :user, content: "Hello"})

      {:ok, _} = AI.delete_conversation(conversation)

      assert AI.get_conversation(conversation.id) == nil
    end
  end

  describe "messages" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      {:ok, conversation} = AI.create_conversation(household.id, user)
      %{user: user, household: household, conversation: conversation}
    end

    test "create_message/2 creates a user message", %{conversation: conversation} do
      {:ok, message} = AI.create_message(conversation.id, %{role: :user, content: "Hello"})

      assert message.role == :user
      assert message.content == "Hello"
      assert message.conversation_id == conversation.id
    end

    test "create_message/2 creates an assistant message", %{conversation: conversation} do
      {:ok, message} =
        AI.create_message(conversation.id, %{role: :assistant, content: "Hi there!"})

      assert message.role == :assistant
    end

    test "create_message/2 with tool_calls", %{conversation: conversation} do
      tool_calls = %{"calls" => [%{"id" => "call_1", "function" => %{"name" => "test"}}]}

      {:ok, message} =
        AI.create_message(conversation.id, %{role: :assistant, tool_calls: tool_calls})

      assert message.tool_calls == tool_calls
    end

    test "list_messages/1 returns messages in order", %{conversation: conversation} do
      {:ok, _msg1} = AI.create_message(conversation.id, %{role: :user, content: "First"})
      {:ok, _msg2} = AI.create_message(conversation.id, %{role: :assistant, content: "Second"})

      messages = AI.list_messages(conversation.id)
      assert length(messages) == 2
      assert hd(messages).content == "First"
    end
  end

  describe "recommended_models/0" do
    test "returns a list of models" do
      models = AI.recommended_models()
      assert is_list(models)
      assert length(models) > 0

      first = hd(models)
      assert Map.has_key?(first, :id)
      assert Map.has_key?(first, :name)
    end
  end

  describe "default_model/0" do
    test "returns the default model" do
      assert AI.default_model() == "anthropic/claude-3.5-sonnet"
    end
  end
end
