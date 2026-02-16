# Cook Dialog Redesign

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the "Cook It" flow so users understand what the button does, see ingredient availability before cooking, and can add missing items to their shopping list.

**Scope:** Feature B only (cook dialog with availability awareness). Feature A (auto-link ingredients at recipe creation) is a follow-up.

## Button Label

Change "Cook It" to "I Cooked This" (or similar) to make the action clearer for new users. The button already links to the cook modal via `push_patch`.

## Cook Dialog Structure

When the cook modal opens, compute availability for each ingredient scaled by the selected servings.

### Ingredient Display

Two groups:

- **Have** (green/success) - pantry quantity >= needed quantity. Show "name: have X, need Y".
- **Need** (amber/warning) - pantry quantity < needed quantity or zero. Show "name: have X, need Y" with visual distinction.

Unlinked ingredients (no `pantry_item_id`) show as "not tracked" in a muted style, not blocking.

### Servings Input

At top of dialog. Changing servings recalculates availability in real-time (no server round-trip needed if we pass pantry quantities to the template; or a simple `handle_event` recompute).

### Actions

Two buttons at the bottom:

- **"Add Missing to List"** - Adds insufficient ingredients to the main shopping list. Reuses existing `Recipes.add_missing_to_list/3` logic. Only shown when there are missing ingredients.
- **"Cook Anyway"** / **"Cooked It!"** - Proceeds with `Recipes.cook_recipe/3`. Decrements available pantry items, clamps to 0. Always available.

Rating and notes fields remain below the ingredient list.

## Data Flow

1. Mount/patch to `:cook` action triggers `apply_action(socket, :cook, params)`
2. `apply_action` computes `ingredient_availability` - a list of `%{ingredient, pantry_quantity, needed_quantity, status}` for each ingredient
3. Template renders the two groups based on `status` (`:have` or `:need`)
4. Servings change event recomputes availability
5. "Add Missing to List" calls existing `Recipes.add_missing_to_list/3`
6. "Cook Anyway" calls existing `Recipes.cook_recipe/3`

## Context Function

Add `Recipes.check_availability/2` that takes a recipe and servings count, returns a list of ingredient availability structs. This is pure computation (no side effects), reusable by both the dialog and potential future features.

## No Schema Changes

No migrations needed. All data already exists (ingredients, pantry items, quantities).
