defmodule FeedMeWeb.RecipeLive.Index do
  use FeedMeWeb, :live_view

  alias FeedMe.Recipes
  alias FeedMe.Recipes.Recipe

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household

    recipes = Recipes.list_recipes(household.id)
    tags = Recipes.list_tags(household.id)

    {:ok,
     socket
     |> assign(:active_tab, :recipes)
     |> assign(:recipes, recipes)
     |> assign(:tags, tags)
     |> assign(:filter_tag, nil)
     |> assign(:filter_favorites, false)
     |> assign(:search_query, "")
     |> assign(:page_title, "Recipes")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Recipes")
    |> assign(:recipe, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Recipe")
    |> assign(:recipe, %Recipe{household_id: socket.assigns.household.id})
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    recipe = Recipes.get_recipe(id, socket.assigns.household.id)

    if recipe do
      {:ok, _} = Recipes.delete_recipe(recipe)

      {:noreply,
       socket
       |> put_flash(:info, "Recipe deleted")
       |> assign(:recipes, Recipes.list_recipes(socket.assigns.household.id))}
    else
      {:noreply, put_flash(socket, :error, "Recipe not found")}
    end
  end

  def handle_event("toggle_favorite", %{"id" => id}, socket) do
    recipe = Recipes.get_recipe(id, socket.assigns.household.id)

    if recipe do
      {:ok, _} = Recipes.toggle_favorite(recipe)

      {:noreply, assign(socket, :recipes, Recipes.list_recipes(socket.assigns.household.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search", %{"query" => query}, socket) do
    recipes =
      if query == "" do
        Recipes.list_recipes(socket.assigns.household.id)
      else
        Recipes.search_recipes(socket.assigns.household.id, query)
      end

    {:noreply, assign(socket, search_query: query, recipes: recipes)}
  end

  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    tag = if tag == "", do: nil, else: tag

    recipes = Recipes.list_recipes(socket.assigns.household.id, tag: tag)

    {:noreply, assign(socket, filter_tag: tag, recipes: recipes)}
  end

  def handle_event("filter_favorites", %{"value" => value}, socket) do
    favorites = value == "true"

    recipes = Recipes.list_recipes(socket.assigns.household.id, favorites_only: favorites)

    {:noreply, assign(socket, filter_favorites: favorites, recipes: recipes)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        Recipes
        <:subtitle>{@household.name}</:subtitle>
        <:actions>
          <.link patch={~p"/households/#{@household.id}/recipes/new"}>
            <.button>New Recipe</.button>
          </.link>
        </:actions>
      </.header>

      <div class="mt-6 flex flex-col sm:flex-row gap-4">
        <div class="flex-1">
          <form phx-change="search" phx-submit="search">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search recipes..."
              class="input input-bordered w-full"
              phx-debounce="300"
            />
          </form>
        </div>
        <div class="flex gap-2">
          <form phx-change="filter_tag">
            <select name="tag" class="select select-bordered">
              <option value="">All Tags</option>
              <%= for tag <- @tags do %>
                <option value={tag} selected={@filter_tag == tag}>{tag}</option>
              <% end %>
            </select>
          </form>
          <label class="btn btn-ghost swap">
            <input
              type="checkbox"
              name="value"
              value={if @filter_favorites, do: "false", else: "true"}
              checked={@filter_favorites}
              phx-change="filter_favorites"
            />
            <div class="swap-off"><.icon name="hero-heart" class="size-5" /></div>
            <div class="swap-on text-error"><.icon name="hero-heart-solid" class="size-5" /></div>
          </label>
        </div>
      </div>

      <div class="mt-6">
        <%= if @recipes == [] do %>
          <div class="text-center py-12 bg-base-200 rounded-lg">
            <.icon name="hero-book-open" class="size-12 mx-auto text-base-content/50" />
            <p class="mt-2 text-base-content/70">No recipes yet.</p>
            <.link patch={~p"/households/#{@household.id}/recipes/new"} class="btn btn-primary mt-4">
              Add your first recipe
            </.link>
          </div>
        <% else %>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <%= for recipe <- @recipes do %>
              <div class="card bg-base-100 shadow-sm border border-base-200 hover:border-primary transition-colors">
                <%= if photo = get_primary_photo(recipe) do %>
                  <figure class="h-40 overflow-hidden">
                    <img src={photo.url} alt={recipe.title} class="w-full h-full object-cover" />
                  </figure>
                <% else %>
                  <figure class="h-40 bg-base-200 flex items-center justify-center">
                    <.icon name="hero-photo" class="size-12 text-base-content/30" />
                  </figure>
                <% end %>
                <div class="card-body p-4">
                  <div class="flex items-start justify-between">
                    <.link navigate={~p"/households/#{@household.id}/recipes/#{recipe.id}"}>
                      <h3 class="card-title text-base hover:text-primary">{recipe.title}</h3>
                    </.link>
                    <button
                      phx-click="toggle_favorite"
                      phx-value-id={recipe.id}
                      class="btn btn-ghost btn-xs"
                    >
                      <%= if recipe.is_favorite do %>
                        <.icon name="hero-heart-solid" class="size-5 text-error" />
                      <% else %>
                        <.icon name="hero-heart" class="size-5" />
                      <% end %>
                    </button>
                  </div>
                  <div class="flex flex-wrap gap-1 mt-2">
                    <%= if Recipe.total_time(recipe) > 0 do %>
                      <span class="badge badge-sm badge-ghost">
                        <.icon name="hero-clock" class="size-3 mr-1" />
                        {Recipe.total_time(recipe)} min
                      </span>
                    <% end %>
                    <%= if recipe.servings do %>
                      <span class="badge badge-sm badge-ghost">
                        <.icon name="hero-users" class="size-3 mr-1" />
                        {recipe.servings}
                      </span>
                    <% end %>
                  </div>
                  <%= if recipe.tags != [] do %>
                    <div class="flex flex-wrap gap-1 mt-2">
                      <%= for tag <- Enum.take(recipe.tags, 3) do %>
                        <span class="badge badge-xs">{tag}</span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <.back navigate={~p"/households/#{@household.id}"}>Back to household</.back>

      <.modal
        :if={@live_action == :new}
        id="recipe-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/recipes")}
      >
        <.live_component
          module={FeedMeWeb.RecipeLive.FormComponent}
          id={:new}
          title="New Recipe"
          action={@live_action}
          recipe={@recipe}
          household={@household}
          current_user={@current_scope.user}
          patch={~p"/households/#{@household.id}/recipes"}
        />
      </.modal>
    </div>
    """
  end

  defp get_primary_photo(recipe) do
    recipe.photos
    |> Enum.find(& &1.is_primary) || List.first(recipe.photos)
  end
end
