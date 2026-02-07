defmodule FeedMeWeb.SettingsLive.ApiKey do
  @moduledoc """
  LiveView for managing AI API keys (BYOK) and model selection.
  """
  use FeedMeWeb, :live_view

  alias FeedMe.AI
  alias FeedMe.Households

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household
    role = socket.assigns.role

    if role != :admin do
      {:ok,
       socket
       |> put_flash(:error, "Only admins can manage API keys")
       |> push_navigate(to: ~p"/households/#{household.id}")}
    else
      api_key = AI.get_api_key(household.id)
      models = if api_key, do: load_models(household.id), else: []

      {:ok,
       socket
       |> assign(:active_tab, :settings)
       |> assign(:api_key, api_key)
       |> assign(:form, to_form(%{"api_key" => ""}))
       |> assign(:validating, false)
       |> assign(:models, models)
       |> assign(:filtered_models, models)
       |> assign(:model_search, "")
       |> assign(:loading_models, false)
       |> assign(:page_title, "API Key Settings")}
    end
  end

  defp load_models(household_id) do
    case AI.list_capable_models(household_id) do
      {:ok, models} -> models
      _ -> []
    end
  end

  @impl true
  def handle_event("save_key", %{"api_key" => api_key}, socket) when api_key != "" do
    user = socket.assigns.current_scope.user
    household = socket.assigns.household

    socket = assign(socket, :validating, true)

    # Validate the key first
    case AI.validate_api_key(api_key) do
      :valid ->
        case AI.set_api_key(household.id, "openrouter", api_key, user) do
          {:ok, saved_key} ->
            {:noreply,
             socket
             |> put_flash(:info, "API key saved successfully")
             |> assign(:api_key, saved_key)
             |> assign(:form, to_form(%{"api_key" => ""}))
             |> assign(:validating, false)}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to save API key")
             |> assign(:validating, false)}
        end

      :invalid ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid API key. Please check and try again.")
         |> assign(:validating, false)}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not validate API key. Please try again.")
         |> assign(:validating, false)}
    end
  end

  def handle_event("save_key", _params, socket), do: {:noreply, socket}

  def handle_event("delete_key", _params, socket) do
    case socket.assigns.api_key do
      nil ->
        {:noreply, socket}

      api_key ->
        {:ok, _} = AI.delete_api_key(api_key)

        {:noreply,
         socket
         |> put_flash(:info, "API key deleted")
         |> assign(:api_key, nil)
         |> assign(:models, [])
         |> assign(:filtered_models, [])}
    end
  end

  def handle_event("search_models", %{"value" => search}, socket) do
    filtered =
      if search == "" do
        socket.assigns.models
      else
        search_lower = String.downcase(search)

        Enum.filter(socket.assigns.models, fn model ->
          String.contains?(String.downcase(model.name || ""), search_lower) or
            String.contains?(String.downcase(model.id || ""), search_lower)
        end)
      end

    {:noreply,
     socket
     |> assign(:model_search, search)
     |> assign(:filtered_models, filtered)}
  end

  def handle_event("select_model", %{"model" => model_id}, socket) do
    household = socket.assigns.household

    case Households.update_household(household, %{selected_model: model_id}) do
      {:ok, updated_household} ->
        {:noreply,
         socket
         |> assign(:household, updated_household)
         |> put_flash(:info, "Model updated to #{model_id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update model")}
    end
  end

  def handle_event("refresh_models", _params, socket) do
    socket = assign(socket, :loading_models, true)
    models = load_models(socket.assigns.household.id)

    {:noreply,
     socket
     |> assign(:models, models)
     |> assign(:filtered_models, filter_by_search(models, socket.assigns.model_search))
     |> assign(:loading_models, false)}
  end

  defp filter_by_search(models, ""), do: models

  defp filter_by_search(models, search) do
    search_lower = String.downcase(search)

    Enum.filter(models, fn model ->
      String.contains?(String.downcase(model.name || ""), search_lower) or
        String.contains?(String.downcase(model.id || ""), search_lower)
    end)
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(num), do: to_string(num)

  defp format_price(nil), do: nil

  defp format_price(price_per_token) when is_binary(price_per_token) do
    case Float.parse(price_per_token) do
      {price, _} -> format_price(price)
      :error -> nil
    end
  end

  defp format_price(price_per_token) when is_number(price_per_token) do
    # Convert from price per token to price per million tokens
    price_per_million = price_per_token * 1_000_000

    cond do
      price_per_million == 0 -> "Free"
      price_per_million < 0.01 -> "<$0.01"
      price_per_million < 1 -> "$#{:erlang.float_to_binary(price_per_million, decimals: 2)}"
      true -> "$#{:erlang.float_to_binary(price_per_million, decimals: 2)}"
    end
  end

  defp get_pricing(model) do
    case model.pricing do
      %{"prompt" => prompt, "completion" => completion} ->
        {format_price(prompt), format_price(completion)}

      _ ->
        {nil, nil}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        AI Settings
        <:subtitle>Configure your AI provider and model</:subtitle>
      </.header>

      <div class="mt-6 space-y-6">
        <!-- Current Model Selection (shown prominently when API key exists) -->
        <%= if @api_key && @api_key.is_valid do %>
          <div class="card bg-primary/10 border-2 border-primary">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <div>
                  <h3 class="text-sm font-medium text-primary">Active AI Model</h3>
                  <p class="text-xl font-semibold mt-1">
                    {get_model_display_name(@household.selected_model, @models)}
                  </p>
                  <p class="text-sm text-base-content/60 font-mono">{@household.selected_model}</p>
                </div>
                <.icon name="hero-cpu-chip" class="h-10 w-10 text-primary" />
              </div>
              <p class="text-sm text-base-content/70 mt-2">
                This model will be used for all new AI conversations.
              </p>
            </div>
          </div>
        <% end %>

        <div class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="card-title">OpenRouter API Key</h3>
            <p class="text-sm text-base-content/70">
              FeedMe uses <a href="https://openrouter.ai" target="_blank" class="link">OpenRouter</a>
              to access AI models. You'll need to create an account and add credits to use AI features.
            </p>

            <%= if @api_key do %>
              <div class="mt-4 p-4 bg-base-200 rounded-lg flex items-center justify-between">
                <div>
                  <p class="font-medium">Current Key</p>
                  <p class="text-sm text-base-content/70 font-mono">{@api_key.key_hint}</p>
                  <p class="text-xs text-base-content/50">
                    Added {Calendar.strftime(@api_key.inserted_at, "%b %d, %Y")}
                    <%= if @api_key.last_used_at do %>
                      · Last used {Calendar.strftime(@api_key.last_used_at, "%b %d, %Y")}
                    <% end %>
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <%= if @api_key.is_valid do %>
                    <span class="badge badge-success">Valid</span>
                  <% else %>
                    <span class="badge badge-error">Invalid</span>
                  <% end %>
                  <button phx-click="delete_key" class="btn btn-ghost btn-sm text-error">
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </div>
              </div>
            <% end %>

            <form phx-submit="save_key" class="mt-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">
                    {if @api_key, do: "Replace API Key", else: "API Key"}
                  </span>
                </label>
                <input
                  type="password"
                  name="api_key"
                  placeholder="sk-or-v1-..."
                  class="input input-bordered"
                  autocomplete="off"
                />
              </div>
              <div class="mt-4">
                <button type="submit" class="btn btn-primary" disabled={@validating}>
                  <%= if @validating do %>
                    <span class="loading loading-spinner loading-sm"></span> Validating...
                  <% else %>
                    {if @api_key, do: "Update Key", else: "Save Key"}
                  <% end %>
                </button>
              </div>
            </form>
          </div>
        </div>

        <%= if !@api_key do %>
          <div class="card bg-base-100 border border-base-200">
            <div class="card-body">
              <h3 class="card-title">How to get an API key</h3>
              <ol class="list-decimal list-inside space-y-2 text-sm">
                <li>
                  Go to <a href="https://openrouter.ai" target="_blank" class="link">openrouter.ai</a>
                </li>
                <li>Create an account or sign in</li>
                <li>Add credits to your account (starts at $5)</li>
                <li>Go to Keys and create a new API key</li>
                <li>Copy the key and paste it above</li>
              </ol>
            </div>
          </div>
        <% end %>

        <%= if @api_key do %>
          <div class="card bg-base-100 border border-base-200">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <h3 class="card-title">Change AI Model</h3>
                <button
                  phx-click="refresh_models"
                  class="btn btn-ghost btn-sm"
                  disabled={@loading_models}
                >
                  <%= if @loading_models do %>
                    <span class="loading loading-spinner loading-sm"></span>
                  <% else %>
                    <.icon name="hero-arrow-path" class="h-4 w-4" />
                  <% end %>
                  Refresh
                </button>
              </div>
              <p class="text-sm text-base-content/70">
                All models below support both <span class="badge badge-success badge-xs">Tools</span>
                and <span class="badge badge-info badge-xs">Vision</span>
                for the best FeedMe experience.
              </p>

              <div class="mt-4">
                <div class="form-control">
                  <input
                    type="text"
                    placeholder="Search models..."
                    value={@model_search}
                    phx-keyup="search_models"
                    phx-debounce="200"
                    name="search"
                    class="input input-bordered"
                  />
                </div>
              </div>

              <%= if @models == [] do %>
                <div class="mt-4 text-center py-8 text-base-content/50">
                  <.icon name="hero-cpu-chip" class="h-12 w-12 mx-auto mb-2" />
                  <p>No models loaded yet.</p>
                  <button phx-click="refresh_models" class="btn btn-primary btn-sm mt-2">
                    Load Models
                  </button>
                </div>
              <% else %>
                <div class="mt-2 text-xs text-base-content/50 text-right">
                  Prices per 1M tokens
                </div>
                <div class="mt-4 max-h-96 overflow-y-auto space-y-2">
                  <%= for model <- @filtered_models do %>
                    <% {input_price, output_price} = get_pricing(model) %>
                    <div
                      phx-click="select_model"
                      phx-value-model={model.id}
                      class={[
                        "p-3 rounded-lg border cursor-pointer transition-colors",
                        if(@household.selected_model == model.id,
                          do: "border-primary bg-primary/10",
                          else: "border-base-300 hover:border-primary/50 hover:bg-base-200"
                        )
                      ]}
                    >
                      <div class="flex items-start justify-between gap-2">
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center gap-2">
                            <span class="font-medium truncate">{model.name}</span>
                            <%= if @household.selected_model == model.id do %>
                              <.icon
                                name="hero-check-circle"
                                class="h-5 w-5 text-primary flex-shrink-0"
                              />
                            <% end %>
                          </div>
                          <div class="text-xs text-base-content/50 font-mono truncate">
                            {model.id}
                          </div>
                        </div>
                        <%= if input_price && output_price do %>
                          <div class="text-right flex-shrink-0">
                            <div class="text-xs font-medium">
                              <span class="text-base-content/70">In:</span>
                              <span class="text-success">{input_price}</span>
                            </div>
                            <div class="text-xs font-medium">
                              <span class="text-base-content/70">Out:</span>
                              <span class="text-warning">{output_price}</span>
                            </div>
                          </div>
                        <% end %>
                      </div>
                      <%= if model.context_length do %>
                        <div class="text-xs text-base-content/50 mt-1">
                          Context: {format_number(model.context_length)} tokens
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <div class="mt-4 text-sm text-base-content/50">
                  Showing {length(@filtered_models)} of {length(@models)} models with Tools + Vision
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <.back navigate={~p"/households/#{@household.id}/settings"}>Back to settings</.back>
    </div>
    """
  end

  defp get_model_display_name(model_id, models) do
    case Enum.find(models, fn m -> m.id == model_id end) do
      nil ->
        model_id
        |> String.split("/")
        |> List.last()
        |> String.replace("-", " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      model ->
        model.name
    end
  end
end
