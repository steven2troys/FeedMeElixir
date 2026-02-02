defmodule FeedMeWeb.RecipeLive.Show do
  use FeedMeWeb, :live_view

  alias FeedMe.Households
  alias FeedMe.Recipes
  alias FeedMe.Recipes.Recipe

  @impl true
  def mount(%{"household_id" => household_id, "id" => recipe_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Households.get_household_for_user(household_id, user) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Household not found")
         |> push_navigate(to: ~p"/households")}

      %{household: household} ->
        recipe = Recipes.get_recipe(recipe_id, household.id)

        if recipe do
          {:ok,
           socket
           |> assign(:household, household)
           |> assign(:recipe, recipe)
           |> assign(:page_title, recipe.title)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Recipe not found")
           |> push_navigate(to: ~p"/households/#{household.id}/recipes")}
        end
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:page_title, socket.assigns.recipe.title)
  end

  defp apply_action(socket, :edit, _params) do
    socket
    |> assign(:page_title, "Edit Recipe")
  end

  defp apply_action(socket, :cook, _params) do
    socket
    |> assign(:page_title, "Cook Recipe")
  end

  @impl true
  def handle_event("toggle_favorite", _params, socket) do
    {:ok, recipe} = Recipes.toggle_favorite(socket.assigns.recipe)
    recipe = Recipes.get_recipe(recipe.id, socket.assigns.household.id)
    {:noreply, assign(socket, recipe: recipe)}
  end

  def handle_event("add_to_list", _params, socket) do
    user = socket.assigns.current_scope.user

    case Recipes.add_missing_to_list(socket.assigns.recipe, socket.assigns.household.id, user) do
      {:ok, %{added: added, already_have: have}} ->
        message =
          cond do
            added == 0 && have > 0 -> "You already have all the ingredients!"
            added > 0 && have > 0 -> "Added #{added} items to shopping list (you have #{have})"
            added > 0 -> "Added #{added} items to shopping list"
            true -> "No ingredients to add"
          end

        {:noreply, put_flash(socket, :info, message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add ingredients")}
    end
  end

  def handle_event("cook_confirmed", %{"servings" => servings, "rating" => rating, "notes" => notes}, socket) do
    user = socket.assigns.current_scope.user

    opts = [
      servings_made: String.to_integer(servings),
      rating: if(rating != "", do: String.to_integer(rating)),
      notes: if(notes != "", do: notes)
    ]

    case Recipes.cook_recipe(socket.assigns.recipe, user, opts) do
      {:ok, _log} ->
        recipe = Recipes.get_recipe(socket.assigns.recipe.id, socket.assigns.household.id)

        {:noreply,
         socket
         |> put_flash(:info, "Enjoy your meal! Pantry updated.")
         |> assign(:recipe, recipe)
         |> push_patch(to: ~p"/households/#{socket.assigns.household.id}/recipes/#{socket.assigns.recipe.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl">
      <.header>
        <%= @recipe.title %>
        <:subtitle>
          <div class="flex flex-wrap gap-2 mt-2">
            <%= if Recipe.total_time(@recipe) > 0 do %>
              <span class="badge badge-ghost">
                <.icon name="hero-clock" class="size-4 mr-1" />
                <%= Recipe.total_time(@recipe) %> min total
              </span>
            <% end %>
            <%= if @recipe.servings do %>
              <span class="badge badge-ghost">
                <.icon name="hero-users" class="size-4 mr-1" />
                <%= @recipe.servings %> servings
              </span>
            <% end %>
            <%= for tag <- @recipe.tags do %>
              <span class="badge badge-sm"><%= tag %></span>
            <% end %>
          </div>
        </:subtitle>
        <:actions>
          <button phx-click="toggle_favorite" class="btn btn-ghost btn-sm">
            <%= if @recipe.is_favorite do %>
              <.icon name="hero-heart-solid" class="size-5 text-error" />
            <% else %>
              <.icon name="hero-heart" class="size-5" />
            <% end %>
          </button>
          <button phx-click="add_to_list" class="btn btn-ghost btn-sm">
            <.icon name="hero-shopping-cart" class="size-5" />
          </button>
          <.link patch={~p"/households/#{@household.id}/recipes/#{@recipe.id}/cook"}>
            <.button>Cook It</.button>
          </.link>
          <.link patch={~p"/households/#{@household.id}/recipes/#{@recipe.id}/edit"}>
            <.button>Edit</.button>
          </.link>
        </:actions>
      </.header>

      <%= if @recipe.photos != [] do %>
        <div class="mt-6 carousel w-full rounded-lg">
          <%= for {photo, idx} <- Enum.with_index(@recipe.photos) do %>
            <div id={"slide-#{idx}"} class="carousel-item relative w-full">
              <img src={photo.url} class="w-full max-h-96 object-cover" alt={photo.caption || @recipe.title} />
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @recipe.description do %>
        <div class="mt-6">
          <p class="text-base-content/80"><%= @recipe.description %></p>
        </div>
      <% end %>

      <div class="mt-8 grid gap-8 lg:grid-cols-3">
        <div class="lg:col-span-1">
          <h3 class="font-semibold text-lg mb-4">Ingredients</h3>
          <ul class="space-y-2">
            <%= for ingredient <- Enum.sort_by(@recipe.ingredients, & &1.sort_order) do %>
              <li class="flex items-start gap-2">
                <span class="badge badge-sm badge-ghost mt-0.5">
                  <%= if ingredient.quantity do %>
                    <%= Decimal.to_string(ingredient.quantity) %><%= if ingredient.unit, do: " #{ingredient.unit}" %>
                  <% else %>
                    -
                  <% end %>
                </span>
                <span class={ingredient.optional && "text-base-content/70"}>
                  <%= ingredient.name %>
                  <%= if ingredient.optional do %>
                    <span class="text-xs">(optional)</span>
                  <% end %>
                </span>
              </li>
            <% end %>
          </ul>
        </div>

        <div class="lg:col-span-2">
          <h3 class="font-semibold text-lg mb-4">Instructions</h3>
          <div class="prose prose-sm max-w-none">
            <%= if @recipe.instructions do %>
              <%= for {step, idx} <- @recipe.instructions |> String.split("\n") |> Enum.with_index(1) do %>
                <p><strong><%= idx %>.</strong> <%= step %></p>
              <% end %>
            <% else %>
              <p class="text-base-content/50">No instructions added yet.</p>
            <% end %>
          </div>
        </div>
      </div>

      <%= if @recipe.source_name || @recipe.source_url do %>
        <div class="mt-8 text-sm text-base-content/70">
          Source:
          <%= if @recipe.source_url do %>
            <a href={@recipe.source_url} target="_blank" class="link"><%= @recipe.source_name || @recipe.source_url %></a>
          <% else %>
            <%= @recipe.source_name %>
          <% end %>
        </div>
      <% end %>

      <%= if @recipe.cooking_logs != [] do %>
        <div class="mt-8">
          <h3 class="font-semibold text-lg mb-4">Cooking History</h3>
          <div class="space-y-2">
            <%= for log <- Enum.take(@recipe.cooking_logs, 5) do %>
              <div class="flex items-center justify-between py-2 border-b border-base-200">
                <div>
                  <span class="text-sm">
                    Cooked by <%= log.cooked_by && log.cooked_by.name || "Unknown" %>
                  </span>
                  <%= if log.rating do %>
                    <span class="ml-2">
                      <%= for _ <- 1..log.rating do %>
                        <.icon name="hero-star-solid" class="size-4 text-warning inline" />
                      <% end %>
                    </span>
                  <% end %>
                </div>
                <span class="text-sm text-base-content/70">
                  <%= Calendar.strftime(log.inserted_at, "%b %d, %Y") %>
                </span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <.back navigate={~p"/households/#{@household.id}/recipes"}>Back to recipes</.back>

      <.modal
        :if={@live_action == :edit}
        id="edit-recipe-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/recipes/#{@recipe.id}")}
      >
        <.live_component
          module={FeedMeWeb.RecipeLive.FormComponent}
          id={@recipe.id}
          title="Edit Recipe"
          action={@live_action}
          recipe={@recipe}
          household={@household}
          current_user={@current_scope.user}
          patch={~p"/households/#{@household.id}/recipes/#{@recipe.id}"}
        />
      </.modal>

      <.modal
        :if={@live_action == :cook}
        id="cook-recipe-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/recipes/#{@recipe.id}")}
      >
        <.header>
          Cook <%= @recipe.title %>
          <:subtitle>This will update your pantry inventory</:subtitle>
        </.header>

        <form phx-submit="cook_confirmed" class="mt-6 space-y-4">
          <.input
            name="servings"
            type="number"
            label="Servings made"
            value={@recipe.servings || 1}
            min="1"
          />
          <.input
            name="rating"
            type="select"
            label="Rating"
            prompt="Rate this meal..."
            options={[{"1 star", "1"}, {"2 stars", "2"}, {"3 stars", "3"}, {"4 stars", "4"}, {"5 stars", "5"}]}
          />
          <.input
            name="notes"
            type="textarea"
            label="Notes (optional)"
            placeholder="How did it turn out?"
          />
          <div class="flex gap-2 justify-end">
            <.link
              patch={~p"/households/#{@household.id}/recipes/#{@recipe.id}"}
              class="btn btn-ghost"
            >
              Cancel
            </.link>
            <.button type="submit" variant="primary">I Cooked It!</.button>
          </div>
        </form>
      </.modal>
    </div>
    """
  end
end
