# Auto-Restock: Pantry to Shopping List

## Problem

When a pantry item is used up or drops below its restock threshold, nothing happens. Users must manually add it to their shopping list.

## Solution

Hook-based listener that reacts to the existing `:restock_needed` PubSub broadcast. Two paths based on item configuration:

1. **Keep-in-stock items** (`always_in_stock == true`): Auto-add to main shopping list immediately. Flash confirms.
2. **Non-keep-in-stock items** (qty hits 0): Show inline prompt on pantry page or toast on other pages. User chooses to add or dismiss.

## Data Flow

```
Pantry.adjust_quantity()
  -> needs_restock? == true
  -> broadcasts {:restock_needed, item}
        |
        v
  RestockHooks (on_mount hook, all household LiveViews)
  handle_info({:restock_needed, item})
        |
        +-- always_in_stock == true:
        |     Skip if already on main shopping list (dedup)
        |     Shopping.add_from_pantry(main_list, item, threshold - current_qty, user)
        |     Flash: "Added {name} to shopping list"
        |
        +-- always_in_stock == false AND qty == 0:
              Add to socket assign :restock_prompts
              Pantry page: inline "Add to list?" on item row
              Other pages: toast prompt with Add/Dismiss
```

## Hook: RestockHooks

- New file: `lib/feed_me_web/live/restock_hooks.ex`
- Attaches in household `live_session` alongside HouseholdHooks and ChatDrawerHooks
- Uses `attach_hook/4` to intercept `handle_info` for `:restock_needed`
- Reuses existing PubSub subscription to `pantry:#{household_id}`

## Shopping Context Addition

- `Shopping.item_on_list?/2` - checks if a pantry item is already on a shopping list (unchecked items only), used for dedup

## UI

### Pantry pages (inline)
- Item row shows "Out of stock - Add to list?" badge with checkmark/dismiss buttons
- Driven by `:restock_prompts` socket assign (MapSet of item info maps)

### Non-pantry pages (toast)
- Floating toast at bottom: "{name} is out - Add to shopping list?" with Add/Dismiss
- Multiple toasts stack
- Auto-dismiss after 30s via JS hook

### Keep-in-stock (flash, all pages)
- Standard `put_flash`: "Added {name} (x{qty}) to shopping list"

## Quantity Calculation

- Keep-in-stock: `threshold - current_qty` (buy enough to reach threshold)
- Non-keep-in-stock prompt: defaults to 1

## Edge Cases

- **Dedup**: Check `Shopping.item_on_list?/2` before auto-adding. Skip silently if already present.
- **Rapid adjustments**: Second broadcast finds item already on list, skips.
- **Prompt lifetime**: Ephemeral (socket assigns). Lost on navigation. Re-triggers on next adjustment.
- **Cooking recipes**: Each ingredient triggers independently. Multiple toasts may stack.
- **User scope**: Uses `@current_scope.user` for `added_by` field.

## Existing Infrastructure Leveraged

- `always_in_stock` and `restock_threshold` fields on Item schema
- `Item.needs_restock?/1` function
- `:restock_needed` PubSub broadcast from `adjust_quantity`
- `Shopping.add_from_pantry/4` with pantry_item_id linking
- `attach_hook` pattern from HouseholdHooks/ChatDrawerHooks
