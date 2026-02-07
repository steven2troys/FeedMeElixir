defmodule FeedMeWeb.RecipeLive.Show do
  use FeedMeWeb, :live_view

  alias FeedMe.AI
  alias FeedMe.AI.{ApiKey, ImageGen}
  alias FeedMe.Recipes
  alias FeedMe.Recipes.Recipe
  alias FeedMe.Uploads

  @impl true
  def mount(%{"id" => recipe_id}, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household
    recipe = Recipes.get_recipe(recipe_id, household.id)

    if recipe do
      {:ok,
       socket
       |> assign(:active_tab, :recipes)
       |> assign(:recipe, recipe)
       |> assign(:page_title, recipe.title)
       |> assign(:generating_image, false)
       |> assign(:image_gen_task_ref, nil)
       |> assign(:show_photo_actions, false)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Recipe not found")
       |> push_navigate(to: ~p"/households/#{household.id}/recipes")}
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

    {:ok, %{added: added, already_have: have}} =
      Recipes.add_missing_to_list(socket.assigns.recipe, socket.assigns.household.id, user)

    message =
      cond do
        added == 0 && have > 0 -> "You already have all the ingredients!"
        added > 0 && have > 0 -> "Added #{added} items to shopping list (you have #{have})"
        added > 0 -> "Added #{added} items to shopping list"
        true -> "No ingredients to add"
      end

    {:noreply, put_flash(socket, :info, message)}
  end

  def handle_event(
        "cook_confirmed",
        %{"servings" => servings, "rating" => rating, "notes" => notes},
        socket
      ) do
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
         |> push_patch(
           to: ~p"/households/#{socket.assigns.household.id}/recipes/#{socket.assigns.recipe.id}"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong")}
    end
  end

  def handle_event("toggle_photo_actions", _params, socket) do
    {:noreply, assign(socket, :show_photo_actions, !socket.assigns.show_photo_actions)}
  end

  def handle_event("generate_image", _params, socket) do
    if socket.assigns.generating_image do
      {:noreply, socket}
    else
      household_id = socket.assigns.household.id

      case AI.get_api_key(household_id, "openrouter") do
        nil ->
          {:noreply, put_flash(socket, :error, "No API key configured. Add one in Settings.")}

        api_key_record ->
          decrypted_key = ApiKey.decrypt_key(api_key_record)
          recipe = socket.assigns.recipe

          task =
            Task.Supervisor.async_nolink(FeedMe.Pantry.SyncTaskSupervisor, fn ->
              ImageGen.generate_recipe_photo(decrypted_key, recipe)
            end)

          {:noreply, assign(socket, generating_image: true, image_gen_task_ref: task.ref)}
      end
    end
  end

  def handle_event("delete_photo", %{"id" => photo_id}, socket) do
    household_id = socket.assigns.household.id

    case Recipes.get_photo(photo_id, household_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Photo not found")}

      photo ->
        {:ok, _} = Recipes.delete_photo(photo)
        recipe = Recipes.get_recipe(socket.assigns.recipe.id, household_id)
        # Reset generating_image as safety valve in case state was stuck
        {:noreply,
         assign(socket, recipe: recipe, generating_image: false, image_gen_task_ref: nil)}
    end
  end

  def handle_event("regenerate_image", %{"id" => photo_id}, socket) do
    household_id = socket.assigns.household.id

    # Delete old photo first
    case Recipes.get_photo(photo_id, household_id) do
      nil -> :ok
      photo -> Recipes.delete_photo(photo)
    end

    recipe = Recipes.get_recipe(socket.assigns.recipe.id, household_id)
    socket = assign(socket, recipe: recipe, generating_image: false, image_gen_task_ref: nil)

    # Trigger new generation
    case AI.get_api_key(household_id, "openrouter") do
      nil ->
        {:noreply, put_flash(socket, :error, "No API key configured. Add one in Settings.")}

      api_key_record ->
        decrypted_key = ApiKey.decrypt_key(api_key_record)

        task =
          Task.Supervisor.async_nolink(FeedMe.Pantry.SyncTaskSupervisor, fn ->
            ImageGen.generate_recipe_photo(decrypted_key, recipe)
          end)

        {:noreply, assign(socket, generating_image: true, image_gen_task_ref: task.ref)}
    end
  end

  def handle_event("set_primary_photo", %{"id" => photo_id}, socket) do
    household_id = socket.assigns.household.id

    case Recipes.get_photo(photo_id, household_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Photo not found")}

      photo ->
        {:ok, _} = Recipes.set_primary_photo(photo)
        recipe = Recipes.get_recipe(socket.assigns.recipe.id, household_id)
        {:noreply, assign(socket, recipe: recipe)}
    end
  end

  @impl true
  def handle_info({:image_selected, base64_data}, socket) do
    recipe = socket.assigns.recipe

    case Uploads.save_recipe_photo(base64_data, recipe.id) do
      {:ok, url_path} ->
        sort_order = Recipes.next_photo_sort_order(recipe.id)
        is_primary = recipe.photos == []

        {:ok, _photo} =
          Recipes.create_photo(%{
            url: url_path,
            recipe_id: recipe.id,
            sort_order: sort_order,
            is_primary: is_primary
          })

        recipe = Recipes.get_recipe(recipe.id, socket.assigns.household.id)
        {:noreply, socket |> assign(recipe: recipe) |> put_flash(:info, "Photo added!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save photo: #{inspect(reason)}")}
    end
  end

  def handle_info({:camera_error, error}, socket) do
    {:noreply, put_flash(socket, :error, "Camera error: #{error}")}
  end

  # Async task success
  def handle_info({ref, {:ok, base64_data}}, socket)
      when ref == socket.assigns.image_gen_task_ref do
    Process.demonitor(ref, [:flush])
    recipe = socket.assigns.recipe

    case Uploads.save_recipe_photo(base64_data, recipe.id) do
      {:ok, url_path} ->
        sort_order = Recipes.next_photo_sort_order(recipe.id)
        is_primary = recipe.photos == []

        {:ok, _photo} =
          Recipes.create_photo(%{
            url: url_path,
            caption: "AI generated",
            recipe_id: recipe.id,
            sort_order: sort_order,
            is_primary: is_primary
          })

        recipe = Recipes.get_recipe(recipe.id, socket.assigns.household.id)

        {:noreply,
         socket
         |> assign(recipe: recipe, generating_image: false, image_gen_task_ref: nil)
         |> put_flash(:info, "AI photo generated!")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(generating_image: false, image_gen_task_ref: nil)
         |> put_flash(:error, "Failed to save generated photo: #{inspect(reason)}")}
    end
  end

  # Async task error
  def handle_info({ref, {:error, reason}}, socket)
      when ref == socket.assigns.image_gen_task_ref do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> assign(generating_image: false, image_gen_task_ref: nil)
     |> put_flash(:error, "Image generation failed: #{inspect(reason)}")}
  end

  # Task process crashed
  def handle_info({:DOWN, ref, :process, _pid, reason}, socket)
      when ref == socket.assigns.image_gen_task_ref do
    {:noreply,
     socket
     |> assign(generating_image: false, image_gen_task_ref: nil)
     |> put_flash(:error, "Image generation crashed: #{inspect(reason)}")}
  end

  # Ignore unrelated DOWN messages
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl">
      <.header>
        {@recipe.title}
        <:subtitle>
          <div class="flex flex-wrap gap-2 mt-2">
            <%= if Recipe.total_time(@recipe) > 0 do %>
              <span class="badge badge-ghost">
                <.icon name="hero-clock" class="size-4 mr-1" />
                {Recipe.total_time(@recipe)} min total
              </span>
            <% end %>
            <%= if @recipe.servings do %>
              <span class="badge badge-ghost">
                <.icon name="hero-users" class="size-4 mr-1" />
                {@recipe.servings} servings
              </span>
            <% end %>
            <%= for tag <- @recipe.tags do %>
              <span class="badge badge-sm">{tag}</span>
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

      <%!-- Photo carousel --%>
      <%= if @recipe.photos != [] do %>
        <div class="mt-6 carousel w-full rounded-lg">
          <%= for {photo, idx} <- Enum.with_index(@recipe.photos) do %>
            <div id={"slide-#{idx}"} class="carousel-item relative w-full">
              <img
                src={photo.url}
                class="w-full max-h-96 object-cover"
                alt={photo.caption || @recipe.title}
              />
              <%= if photo.is_primary do %>
                <span class="absolute top-2 left-2 badge badge-primary badge-sm">Primary</span>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Photo action buttons --%>
      <div class="mt-4 flex flex-wrap items-center gap-2">
        <.live_component
          module={FeedMeWeb.ChatLive.CameraComponent}
          id="recipe-camera"
        />

        <button
          phx-click="generate_image"
          class="btn btn-ghost btn-sm"
          disabled={@generating_image}
        >
          <%= if @generating_image do %>
            <span class="loading loading-spinner loading-xs"></span> Generating...
          <% else %>
            <.icon name="hero-sparkles" class="size-4" /> AI Photo
          <% end %>
        </button>

        <%= if @recipe.photos != [] do %>
          <button phx-click="toggle_photo_actions" class="btn btn-ghost btn-sm">
            <.icon name="hero-ellipsis-horizontal" class="size-4" /> Manage
          </button>
        <% end %>
      </div>

      <%!-- Photo management panel --%>
      <%= if @show_photo_actions && @recipe.photos != [] do %>
        <div class="mt-2 p-3 bg-base-200 rounded-lg space-y-2">
          <%= for photo <- @recipe.photos do %>
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <img src={photo.url} class="w-12 h-12 rounded object-cover" alt="" />
                <span class="text-sm">
                  {photo.caption || "Photo"}
                  <%= if photo.is_primary do %>
                    <span class="badge badge-primary badge-xs ml-1">Primary</span>
                  <% end %>
                </span>
              </div>
              <div class="flex gap-1">
                <%= if photo.caption == "AI generated" do %>
                  <button
                    phx-click="regenerate_image"
                    phx-value-id={photo.id}
                    class="btn btn-ghost btn-xs"
                    disabled={@generating_image}
                    title="Regenerate AI photo"
                  >
                    <.icon name="hero-arrow-path" class="size-4" />
                  </button>
                <% end %>
                <%= unless photo.is_primary do %>
                  <button
                    phx-click="set_primary_photo"
                    phx-value-id={photo.id}
                    class="btn btn-ghost btn-xs"
                    title="Set as primary"
                  >
                    <.icon name="hero-star" class="size-4" />
                  </button>
                <% end %>
                <button
                  phx-click="delete_photo"
                  phx-value-id={photo.id}
                  data-confirm="Delete this photo?"
                  class="btn btn-ghost btn-xs text-error"
                  title="Delete photo"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @recipe.description do %>
        <div class="mt-6">
          <p class="text-base-content/80">{@recipe.description}</p>
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
                    {Decimal.to_string(ingredient.quantity)}{if ingredient.unit,
                      do: " #{ingredient.unit}"}
                  <% else %>
                    -
                  <% end %>
                </span>
                <span class={ingredient.optional && "text-base-content/70"}>
                  {ingredient.name}
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
              <ol class="list-decimal pl-5 space-y-2">
                <%= for step <- @recipe.instructions |> String.split("\n") |> Enum.reject(&(&1 == "")) do %>
                  <li>{Regex.replace(~r/^\d+[\.\)]\s*/, step, "")}</li>
                <% end %>
              </ol>
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
            <a href={@recipe.source_url} target="_blank" class="link">
              {@recipe.source_name || @recipe.source_url}
            </a>
          <% else %>
            {@recipe.source_name}
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
                    Cooked by {(log.cooked_by && log.cooked_by.name) || "Unknown"}
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
                  {Calendar.strftime(log.inserted_at, "%b %d, %Y")}
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
          Cook {@recipe.title}
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
            options={[
              {"1 star", "1"},
              {"2 stars", "2"},
              {"3 stars", "3"},
              {"4 stars", "4"},
              {"5 stars", "5"}
            ]}
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
