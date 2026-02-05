defmodule FeedMeWeb.PantryLive.Categories do
  use FeedMeWeb, :live_view

  alias FeedMe.Pantry
  alias FeedMe.Pantry.Category

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household
    categories = Pantry.list_categories(household.id)

    {:ok,
     socket
     |> assign(:active_tab, :pantry)
     |> assign(:categories, categories)
     |> assign(:editing, nil)
     |> assign(:new_category, nil)
     |> assign(:page_title, "Pantry Categories")}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, :new_category, %Category{household_id: socket.assigns.household.id})}
  end

  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, :new_category, nil)}
  end

  def handle_event("create", %{"category" => params}, socket) do
    params = Map.put(params, "household_id", socket.assigns.household.id)

    case Pantry.create_category(params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created")
         |> assign(:new_category, nil)
         |> assign(:categories, Pantry.list_categories(socket.assigns.household.id))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create category: #{error_messages(changeset)}")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    category = Pantry.get_category(id, socket.assigns.household.id)
    {:noreply, assign(socket, :editing, category)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("update", %{"category" => params}, socket) do
    case Pantry.update_category(socket.assigns.editing, params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated")
         |> assign(:editing, nil)
         |> assign(:categories, Pantry.list_categories(socket.assigns.household.id))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update: #{error_messages(changeset)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    category = Pantry.get_category(id, socket.assigns.household.id)

    if category do
      case Pantry.delete_category(category) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Category deleted")
           |> assign(:categories, Pantry.list_categories(socket.assigns.household.id))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete category")}
      end
    else
      {:noreply, put_flash(socket, :error, "Category not found")}
    end
  end

  def handle_event("create_defaults", _params, socket) do
    Pantry.create_default_categories(socket.assigns.household.id)

    {:noreply,
     socket
     |> put_flash(:info, "Default categories created")
     |> assign(:categories, Pantry.list_categories(socket.assigns.household.id))}
  end

  defp error_messages(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map(fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        Pantry Categories
        <:subtitle><%= @household.name %></:subtitle>
        <:actions>
          <button phx-click="new" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> Add Category
          </button>
        </:actions>
      </.header>

      <div class="mt-6">
        <%= if @categories == [] do %>
          <div class="text-center py-12 bg-base-200 rounded-lg">
            <.icon name="hero-tag" class="size-12 mx-auto text-base-content/50" />
            <p class="mt-2 text-base-content/70">No categories yet.</p>
            <button phx-click="create_defaults" class="btn btn-primary mt-4">
              Create Default Categories
            </button>
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for category <- @categories do %>
              <div class="card bg-base-100 shadow-sm border border-base-200">
                <div class="card-body p-4 flex-row items-center justify-between">
                  <%= if @editing && @editing.id == category.id do %>
                    <form phx-submit="update" class="flex-1 flex gap-2">
                      <input
                        type="text"
                        name="category[name]"
                        value={@editing.name}
                        class="input input-bordered flex-1"
                        autofocus
                      />
                      <button type="submit" class="btn btn-primary btn-sm">Save</button>
                      <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">Cancel</button>
                    </form>
                  <% else %>
                    <div class="flex items-center gap-3">
                      <%= if category.icon do %>
                        <span class="text-base-content/70">
                          <.icon name={category.icon} class="size-5" />
                        </span>
                      <% end %>
                      <span class="font-medium"><%= category.name %></span>
                    </div>
                    <div class="flex items-center gap-1">
                      <button phx-click="edit" phx-value-id={category.id} class="btn btn-ghost btn-sm">
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        phx-click="delete"
                        phx-value-id={category.id}
                        data-confirm="Are you sure? Items in this category will become uncategorized."
                        class="btn btn-ghost btn-sm text-error"
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @new_category do %>
          <div class="mt-4 card bg-base-100 shadow border border-primary">
            <div class="card-body p-4">
              <form phx-submit="create" class="flex gap-2">
                <input
                  type="text"
                  name="category[name]"
                  placeholder="Category name..."
                  class="input input-bordered flex-1"
                  autofocus
                />
                <button type="submit" class="btn btn-primary">Create</button>
                <button type="button" phx-click="cancel_new" class="btn btn-ghost">Cancel</button>
              </form>
            </div>
          </div>
        <% end %>
      </div>

      <.back navigate={~p"/households/#{@household.id}/pantry"}>Back to pantry</.back>
    </div>
    """
  end
end
