defmodule FeedMeWeb.RecipeLive.FormComponent do
  use FeedMeWeb, :live_component

  alias FeedMe.Recipes
  alias FeedMe.Recipes.Recipe

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.simple_form
        for={@form}
        id="recipe-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:description]} type="textarea" label="Description" rows="2" />

        <div class="grid grid-cols-3 gap-4">
          <.input field={@form[:prep_time_minutes]} type="number" label="Prep (min)" min="0" />
          <.input field={@form[:cook_time_minutes]} type="number" label="Cook (min)" min="0" />
          <.input field={@form[:servings]} type="number" label="Servings" min="1" />
        </div>

        <.input field={@form[:instructions]} type="textarea" label="Instructions" rows="6" />

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:source_name]}
            type="text"
            label="Source"
            placeholder="e.g., Grandma's cookbook"
          />
          <.input field={@form[:source_url]} type="url" label="Source URL" placeholder="https://..." />
        </div>

        <.input
          field={@form[:tags]}
          type="text"
          label="Tags"
          placeholder="dinner, quick, vegetarian (comma-separated)"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Recipe</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{recipe: recipe} = assigns, socket) do
    form_data =
      if recipe.tags && is_list(recipe.tags) do
        %{recipe | tags: Enum.join(recipe.tags, ", ")}
      else
        recipe
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Recipe.changeset(form_data, %{}))
     end)}
  end

  @impl true
  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    recipe_params = normalize_tags(recipe_params)

    changeset =
      socket.assigns.recipe
      |> Recipe.changeset(recipe_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    recipe_params = normalize_tags(recipe_params)
    save_recipe(socket, socket.assigns.action, recipe_params)
  end

  defp normalize_tags(params) do
    case params["tags"] do
      nil ->
        params

      tags when is_binary(tags) ->
        tag_list =
          tags
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "tags", tag_list)

      _ ->
        params
    end
  end

  defp save_recipe(socket, :new, recipe_params) do
    params =
      recipe_params
      |> Map.put("household_id", socket.assigns.household.id)
      |> Map.put("created_by_id", socket.assigns.current_user.id)

    case Recipes.create_recipe(params) do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe created successfully")
         |> push_navigate(to: ~p"/households/#{socket.assigns.household.id}/recipes/#{recipe.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_recipe(socket, :edit, recipe_params) do
    case Recipes.update_recipe(socket.assigns.recipe, recipe_params) do
      {:ok, _recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
