defmodule FeedMeWeb.PantryLive.Categories do
  use FeedMeWeb, :live_view

  alias FeedMe.Pantry
  alias FeedMe.Pantry.Category

  @impl true
  def mount(params, _session, socket) do
    household = socket.assigns.household
    location_id = params["location_id"]

    location =
      if location_id do
        Pantry.get_storage_location(location_id, household.id)
      else
        Pantry.get_pantry_location(household.id) ||
          Pantry.get_default_storage_location(household.id)
      end

    if location do
      categories = Pantry.list_categories(location.id)

      {:ok,
       socket
       |> assign(:active_tab, :pantry)
       |> assign(:location, location)
       |> assign(:categories, categories)
       |> assign(:editing, nil)
       |> assign(:new_category, nil)
       |> assign(:page_title, "#{location.name} Categories")}
    else
      {:ok,
       socket
       |> put_flash(:error, "Location not found")
       |> push_navigate(to: ~p"/households/#{household.id}/pantry")}
    end
  end

  @impl true
  def handle_event("new", _params, socket) do
    location = socket.assigns.location

    {:noreply,
     assign(socket, :new_category, %Category{
       household_id: socket.assigns.household.id,
       storage_location_id: location.id
     })}
  end

  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, :new_category, nil)}
  end

  def handle_event("create", %{"category" => params}, socket) do
    location = socket.assigns.location

    params =
      params
      |> Map.put("household_id", socket.assigns.household.id)
      |> Map.put("storage_location_id", location.id)

    case Pantry.create_category(params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created")
         |> assign(:new_category, nil)
         |> assign(:categories, Pantry.list_categories(location.id))}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create category: #{error_messages(changeset)}")}
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
    location = socket.assigns.location

    case Pantry.update_category(socket.assigns.editing, params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated")
         |> assign(:editing, nil)
         |> assign(:categories, Pantry.list_categories(location.id))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update: #{error_messages(changeset)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    category = Pantry.get_category(id, socket.assigns.household.id)
    location = socket.assigns.location

    if category do
      case Pantry.delete_category(category) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Category deleted")
           |> assign(:categories, Pantry.list_categories(location.id))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete category")}
      end
    else
      {:noreply, put_flash(socket, :error, "Category not found")}
    end
  end

  def handle_event("create_defaults", _params, socket) do
    location = socket.assigns.location
    template = Pantry.suggest_template(location.name) || :pantry
    Pantry.create_default_categories(location.id, socket.assigns.household.id, template)

    {:noreply,
     socket
     |> put_flash(:info, "Default categories created")
     |> assign(:categories, Pantry.list_categories(location.id))}
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
        {@location.name} Categories
        <:subtitle>{@household.name}</:subtitle>
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
                      <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                        Cancel
                      </button>
                    </form>
                  <% else %>
                    <div class="flex items-center gap-3">
                      <%= if category.icon do %>
                        <span class="text-base-content/70">
                          <.icon name={category.icon} class="size-5" />
                        </span>
                      <% end %>
                      <span class="font-medium">{category.name}</span>
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

      <.back navigate={~p"/households/#{@household.id}/pantry/locations/#{@location.id}"}>
        Back to {@location.name}
      </.back>
    </div>
    """
  end
end
