defmodule FeedMeWeb.RestockPrompt do
  use Phoenix.Component

  import FeedMeWeb.CoreComponents, only: [icon: 1]

  attr :restock_prompts, :map, required: true
  attr :on_pantry_page, :boolean, default: false

  def restock_toasts(assigns) do
    ~H"""
    <div
      :if={@restock_prompts != %{} and not @on_pantry_page}
      class="fixed bottom-20 md:bottom-4 right-4 z-50 flex flex-col gap-2"
    >
      <div
        :for={{item_id, prompt} <- @restock_prompts}
        id={"restock-toast-#{item_id}"}
        phx-hook="RestockToast"
        class="alert alert-warning shadow-lg w-80"
      >
        <div class="flex items-center justify-between w-full gap-2">
          <span class="text-sm font-medium truncate">{prompt.name} is out</span>
          <div class="flex gap-1 flex-shrink-0">
            <button
              phx-click="add_to_shopping"
              phx-value-item-id={item_id}
              class="btn btn-xs btn-info"
            >
              Add to list
            </button>
            <button
              phx-click="dismiss_restock"
              phx-value-item-id={item_id}
              class="btn btn-xs btn-ghost"
            >
              <.icon name="hero-x-mark" class="size-3" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
