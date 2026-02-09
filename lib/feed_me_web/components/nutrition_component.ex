defmodule FeedMeWeb.NutritionComponent do
  @moduledoc """
  Function components for displaying nutritional information.
  """
  use Phoenix.Component

  import FeedMeWeb.CoreComponents, only: [icon: 1]

  @doc """
  Compact inline badge for list views.

  Displays: "142 cal | 6g P | 20g C | 4g F"
  """
  attr :nutrition, :any, default: nil
  attr :display, :string, default: "none"

  def nutrition_badge(assigns) do
    assigns =
      assign(assigns, :filtered, FeedMe.Nutrition.for_display(assigns.nutrition, assigns.display))

    ~H"""
    <%= if @filtered do %>
      <span class="text-xs text-base-content/60">
        <%= if is_map(@filtered) do %>
          <%= if cal = @filtered[:calories] || Map.get(@filtered, :calories) do %>
            {Decimal.round(cal, 0)} cal
          <% end %>
          <%= if p = @filtered[:protein_g] || Map.get(@filtered, :protein_g) do %>
            <span class="mx-0.5">|</span>{Decimal.round(p, 0)}g P
          <% end %>
          <%= if c = @filtered[:carbs_g] || Map.get(@filtered, :carbs_g) do %>
            <span class="mx-0.5">|</span>{Decimal.round(c, 0)}g C
          <% end %>
          <%= if f = @filtered[:fat_g] || Map.get(@filtered, :fat_g) do %>
            <span class="mx-0.5">|</span>{Decimal.round(f, 0)}g F
          <% end %>
        <% end %>
      </span>
    <% end %>
    """
  end

  @doc """
  Full nutrition card for detail views.
  """
  attr :nutrition, :any, default: nil
  attr :display, :string, default: "none"
  attr :title, :string, default: "Nutrition"

  def nutrition_card(assigns) do
    ~H"""
    <%= if @display != "none" and @nutrition do %>
      <div class="card bg-base-100 shadow border border-base-200">
        <div class="card-body">
          <h3 class="card-title text-sm">
            {@title}
            <%= if @nutrition.source == "ai_estimated" do %>
              <span class="badge badge-xs badge-ghost">AI Estimate</span>
            <% end %>
          </h3>
          <%= if @nutrition.serving_size do %>
            <p class="text-xs text-base-content/60">
              Per {@nutrition.serving_size}
            </p>
          <% end %>
          <div class="grid grid-cols-2 gap-2 mt-2">
            <.nutrient_row label="Calories" value={@nutrition.calories} />
            <.nutrient_row label="Protein" value={@nutrition.protein_g} unit="g" />
            <.nutrient_row label="Carbs" value={@nutrition.carbs_g} unit="g" />
            <.nutrient_row label="Fat" value={@nutrition.fat_g} unit="g" />
          </div>

          <%= if @display == "detailed" do %>
            <div class="divider my-1 text-xs text-base-content/50">Details</div>
            <div class="grid grid-cols-2 gap-2">
              <.nutrient_row label="Sat. Fat" value={@nutrition.saturated_fat_g} unit="g" />
              <.nutrient_row label="Fiber" value={@nutrition.fiber_g} unit="g" />
              <.nutrient_row label="Sugar" value={@nutrition.sugar_g} unit="g" />
              <.nutrient_row label="Sodium" value={@nutrition.sodium_mg} unit="mg" />
              <.nutrient_row label="Cholesterol" value={@nutrition.cholesterol_mg} unit="mg" />
            </div>

            <div class="divider my-1 text-xs text-base-content/50">Vitamins & Minerals</div>
            <div class="grid grid-cols-2 gap-2">
              <.nutrient_row label="Vitamin A" value={@nutrition.vitamin_a_mcg} unit="mcg" />
              <.nutrient_row label="Vitamin C" value={@nutrition.vitamin_c_mg} unit="mg" />
              <.nutrient_row label="Vitamin D" value={@nutrition.vitamin_d_mcg} unit="mcg" />
              <.nutrient_row label="Vitamin K" value={@nutrition.vitamin_k_mcg} unit="mcg" />
              <.nutrient_row label="Calcium" value={@nutrition.calcium_mg} unit="mg" />
              <.nutrient_row label="Iron" value={@nutrition.iron_mg} unit="mg" />
              <.nutrient_row label="Potassium" value={@nutrition.potassium_mg} unit="mg" />
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Recipe per-serving nutrition summary card.
  """
  attr :nutrition, :any, default: nil
  attr :display, :string, default: "none"
  attr :servings, :integer, default: nil

  def nutrition_summary(assigns) do
    ~H"""
    <%= if @display != "none" and @nutrition do %>
      <div class="card bg-base-100 shadow border border-base-200">
        <div class="card-body">
          <h3 class="card-title text-sm">
            <.icon name="hero-beaker" class="size-4" /> Nutrition per Serving
            <%= if @servings do %>
              <span class="text-xs font-normal text-base-content/60">
                ({@servings} servings)
              </span>
            <% end %>
          </h3>
          <div class="flex flex-wrap gap-4 mt-2">
            <.macro_pill label="Cal" value={@nutrition.calories} />
            <.macro_pill label="Protein" value={@nutrition.protein_g} unit="g" />
            <.macro_pill label="Carbs" value={@nutrition.carbs_g} unit="g" />
            <.macro_pill label="Fat" value={@nutrition.fat_g} unit="g" />
          </div>

          <%= if @display == "detailed" do %>
            <div class="grid grid-cols-3 gap-2 mt-3 text-sm">
              <.nutrient_row label="Fiber" value={@nutrition.fiber_g} unit="g" />
              <.nutrient_row label="Sugar" value={@nutrition.sugar_g} unit="g" />
              <.nutrient_row label="Sodium" value={@nutrition.sodium_mg} unit="mg" />
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp nutrient_row(assigns) do
    assigns = Map.put_new(assigns, :unit, nil)

    ~H"""
    <%= if @value do %>
      <div class="flex justify-between text-sm">
        <span class="text-base-content/70">{@label}</span>
        <span class="font-medium">
          {Decimal.round(@value, 1)}{if @unit, do: " #{@unit}"}
        </span>
      </div>
    <% end %>
    """
  end

  defp macro_pill(assigns) do
    assigns = Map.put_new(assigns, :unit, nil)

    ~H"""
    <%= if @value do %>
      <div class="text-center">
        <div class="text-lg font-bold">
          {Decimal.round(@value, 0)}<span class="text-xs font-normal">{@unit}</span>
        </div>
        <div class="text-xs text-base-content/60">{@label}</div>
      </div>
    <% end %>
    """
  end
end
