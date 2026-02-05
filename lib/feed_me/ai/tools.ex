defmodule FeedMe.AI.Tools do
  @moduledoc """
  AI tool definitions and execution for FeedMe assistant.
  """

  alias FeedMe.{Pantry, Profiles, Recipes, Shopping}
  alias FeedMe.AI.{ApiKey, OpenRouter}

  @doc """
  Returns all tool definitions for the AI.
  """
  def definitions do
    [
      add_to_pantry(),
      add_to_shopping_list(),
      search_recipes(),
      get_taste_profiles(),
      check_pantry(),
      get_pantry_categories(),
      suggest_recipe(),
      search_web(),
      add_recipe()
    ]
  end

  @doc """
  Executes a tool call and returns the result.
  """
  def execute(tool_name, args, context) do
    case tool_name do
      "add_to_pantry" -> execute_add_to_pantry(args, context)
      "add_to_shopping_list" -> execute_add_to_shopping_list(args, context)
      "search_recipes" -> execute_search_recipes(args, context)
      "get_taste_profiles" -> execute_get_taste_profiles(args, context)
      "check_pantry" -> execute_check_pantry(args, context)
      "get_pantry_categories" -> execute_get_pantry_categories(args, context)
      "suggest_recipe" -> execute_suggest_recipe(args, context)
      "search_web" -> execute_search_web(args, context)
      "add_recipe" -> execute_add_recipe(args, context)
      _ -> {:error, "Unknown tool: #{tool_name}"}
    end
  end

  # Tool definitions

  defp add_to_pantry do
    %{
      type: "function",
      function: %{
        name: "add_to_pantry",
        description: "Add an item to the household's pantry inventory",
        parameters: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Name of the item"},
            quantity: %{type: "number", description: "Quantity of the item"},
            unit: %{type: "string", description: "Unit of measurement (e.g., 'lbs', 'oz', 'cups')"},
            category: %{type: "string", description: "Category name (e.g., 'Produce', 'Dairy')"},
            expiration_date: %{type: "string", description: "Expiration date in YYYY-MM-DD format"}
          },
          required: ["name"]
        }
      }
    }
  end

  defp add_to_shopping_list do
    %{
      type: "function",
      function: %{
        name: "add_to_shopping_list",
        description: "Add an item to the main shopping list",
        parameters: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Name of the item"},
            quantity: %{type: "number", description: "Quantity needed"},
            unit: %{type: "string", description: "Unit of measurement"},
            notes: %{type: "string", description: "Additional notes about the item"}
          },
          required: ["name"]
        }
      }
    }
  end

  defp search_recipes do
    %{
      type: "function",
      function: %{
        name: "search_recipes",
        description: "Search for recipes in the household's recipe book",
        parameters: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "Search term for recipe title or description"},
            tag: %{type: "string", description: "Filter by tag (e.g., 'dinner', 'quick', 'vegetarian')"},
            favorites_only: %{type: "boolean", description: "Only return favorite recipes"}
          }
        }
      }
    }
  end

  defp get_taste_profiles do
    %{
      type: "function",
      function: %{
        name: "get_taste_profiles",
        description: "Get the household's taste profile including dietary restrictions, allergies, and preferences",
        parameters: %{
          type: "object",
          properties: %{}
        }
      }
    }
  end

  defp check_pantry do
    %{
      type: "function",
      function: %{
        name: "check_pantry",
        description: "Check what items are in the pantry, optionally searching by name",
        parameters: %{
          type: "object",
          properties: %{
            search: %{type: "string", description: "Optional search term to filter pantry items"},
            category: %{type: "string", description: "Optional category to filter by"},
            low_stock_only: %{type: "boolean", description: "Only return items that need restocking"}
          }
        }
      }
    }
  end

  defp get_pantry_categories do
    %{
      type: "function",
      function: %{
        name: "get_pantry_categories",
        description: "Get the list of pantry categories for the household",
        parameters: %{
          type: "object",
          properties: %{}
        }
      }
    }
  end

  defp suggest_recipe do
    %{
      type: "function",
      function: %{
        name: "suggest_recipe",
        description: "Get recipe suggestions based on available pantry items",
        parameters: %{
          type: "object",
          properties: %{
            use_pantry_items: %{type: "boolean", description: "Prioritize recipes using pantry items"},
            max_missing: %{type: "integer", description: "Maximum number of missing ingredients"}
          }
        }
      }
    }
  end

  defp search_web do
    %{
      type: "function",
      function: %{
        name: "search_web",
        description: "Search the web for recipes, cooking techniques, ingredient substitutions, food information, or any other culinary knowledge not in the household's recipe book",
        parameters: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "The search query - be specific and include relevant context (e.g., 'authentic Italian carbonara recipe' or 'substitute for buttermilk in baking')"
            }
          },
          required: ["query"]
        }
      }
    }
  end

  defp add_recipe do
    %{
      type: "function",
      function: %{
        name: "add_recipe",
        description: "Add a new recipe to the household's recipe book. Use this when the user wants to save a recipe you found or know from your training.",
        parameters: %{
          type: "object",
          properties: %{
            title: %{type: "string", description: "The recipe title"},
            description: %{type: "string", description: "A brief description of the dish"},
            instructions: %{type: "string", description: "Step-by-step cooking instructions"},
            ingredients: %{
              type: "array",
              description: "List of ingredients",
              items: %{
                type: "object",
                properties: %{
                  name: %{type: "string", description: "Ingredient name"},
                  quantity: %{type: "number", description: "Amount needed"},
                  unit: %{type: "string", description: "Unit of measurement (e.g., 'cups', 'tbsp', 'oz')"},
                  notes: %{type: "string", description: "Optional notes (e.g., 'diced', 'room temperature')"},
                  optional: %{type: "boolean", description: "Whether this ingredient is optional"}
                },
                required: ["name"]
              }
            },
            prep_time_minutes: %{type: "integer", description: "Preparation time in minutes"},
            cook_time_minutes: %{type: "integer", description: "Cooking time in minutes"},
            servings: %{type: "integer", description: "Number of servings"},
            source_url: %{type: "string", description: "URL where the recipe was found (if applicable)"},
            source_name: %{type: "string", description: "Name of the source (e.g., 'New York Times Cooking', 'Grandma's cookbook')"},
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Tags for categorization (e.g., 'dinner', 'vegetarian', 'quick', 'italian')"
            }
          },
          required: ["title", "instructions", "ingredients"]
        }
      }
    }
  end

  # Tool execution

  defp execute_add_to_pantry(args, %{household_id: household_id, user: user}) do
    # Find or create category
    category_id =
      if args["category"] do
        case Pantry.find_or_create_category(household_id, args["category"]) do
          {:ok, category} -> category.id
          _ -> nil
        end
      end

    attrs = %{
      name: args["name"],
      quantity: args["quantity"] && Decimal.new("#{args["quantity"]}"),
      unit: args["unit"],
      category_id: category_id,
      household_id: household_id,
      expiration_date: parse_date(args["expiration_date"])
    }

    case Pantry.create_item(attrs, user) do
      {:ok, item} ->
        {:ok, "Added #{item.name} to pantry" <> if(item.quantity, do: " (#{item.quantity} #{item.unit || "units"})", else: "")}

      {:error, changeset} ->
        {:error, "Failed to add item: #{inspect(changeset.errors)}"}
    end
  end

  defp execute_add_to_shopping_list(args, %{household_id: household_id, user: user}) do
    list = Shopping.get_or_create_main_list(household_id)

    attrs = %{
      name: args["name"],
      quantity: args["quantity"] && Decimal.new("#{args["quantity"]}"),
      unit: args["unit"],
      notes: args["notes"],
      shopping_list_id: list.id,
      added_by_id: user.id
    }

    case Shopping.create_item(attrs) do
      {:ok, item} ->
        {:ok, "Added #{item.name} to shopping list"}

      {:error, changeset} ->
        {:error, "Failed to add item: #{inspect(changeset.errors)}"}
    end
  end

  defp execute_search_recipes(args, %{household_id: household_id}) do
    recipes =
      cond do
        args["query"] ->
          Recipes.search_recipes(household_id, args["query"])

        true ->
          opts =
            []
            |> maybe_add_opt(:tag, args["tag"])
            |> maybe_add_opt(:favorites_only, args["favorites_only"])

          Recipes.list_recipes(household_id, opts)
      end
      |> Enum.take(10)

    if recipes == [] do
      {:ok, "No recipes found matching your criteria."}
    else
      result =
        recipes
        |> Enum.map(fn r ->
          time = FeedMe.Recipes.Recipe.total_time(r)
          time_str = if time > 0, do: " (#{time} min)", else: ""
          "- #{r.title}#{time_str}" <> if(r.is_favorite, do: " ⭐", else: "")
        end)
        |> Enum.join("\n")

      {:ok, "Found #{length(recipes)} recipes:\n#{result}"}
    end
  end

  defp execute_get_taste_profiles(_args, %{household_id: household_id}) do
    case Profiles.get_or_create_profile(household_id) do
      {:ok, profile} ->
        summary = Profiles.dietary_summary(profile)

        restrictions =
          if profile.dietary_restrictions != [],
            do: "\n- Dietary restrictions: #{Enum.join(profile.dietary_restrictions, ", ")}",
            else: ""

        allergies =
          if profile.allergies != [],
            do: "\n- Allergies: #{Enum.join(profile.allergies, ", ")}",
            else: ""

        dislikes =
          if profile.dislikes != [],
            do: "\n- Dislikes: #{Enum.join(profile.dislikes, ", ")}",
            else: ""

        favorites =
          if profile.favorites != [],
            do: "\n- Favorites: #{Enum.join(profile.favorites, ", ")}",
            else: ""

        {:ok, "Taste Profile Summary: #{summary}#{restrictions}#{allergies}#{dislikes}#{favorites}"}

      {:error, _} ->
        {:ok, "No taste profile set up yet."}
    end
  end

  defp execute_check_pantry(args, %{household_id: household_id}) do
    items =
      cond do
        args["search"] ->
          Pantry.search_items(household_id, args["search"])

        args["low_stock_only"] ->
          Pantry.list_items_needing_restock(household_id)

        args["category"] ->
          case Pantry.get_category_by_name(household_id, args["category"]) do
            nil -> []
            cat -> Pantry.list_items(household_id, category_id: cat.id)
          end

        true ->
          Pantry.list_items(household_id) |> Enum.take(20)
      end

    if items == [] do
      {:ok, "No items found in pantry matching your criteria."}
    else
      result =
        items
        |> Enum.take(15)
        |> Enum.map(fn item ->
          qty = if item.quantity, do: " (#{Decimal.to_string(item.quantity)} #{item.unit || ""})", else: ""
          low = if Pantry.needs_restock?(item), do: " ⚠️ LOW", else: ""
          "- #{item.name}#{qty}#{low}"
        end)
        |> Enum.join("\n")

      {:ok, "Pantry items:\n#{result}"}
    end
  end

  defp execute_get_pantry_categories(_args, %{household_id: household_id}) do
    categories = Pantry.list_categories(household_id)

    if categories == [] do
      {:ok, "No pantry categories set up yet."}
    else
      result = categories |> Enum.map(& &1.name) |> Enum.join(", ")
      {:ok, "Pantry categories: #{result}"}
    end
  end

  defp execute_suggest_recipe(args, %{household_id: household_id}) do
    recipes = Recipes.list_recipes(household_id)

    if recipes == [] do
      {:ok, "No recipes in your recipe book yet. Would you like to add some?"}
    else
      # Get pantry items for matching
      pantry_items =
        Pantry.list_items(household_id)
        |> Enum.map(& &1.name)
        |> Enum.map(&String.downcase/1)
        |> MapSet.new()

      max_missing = args["max_missing"] || 3

      # Score recipes by how many ingredients we have
      scored =
        recipes
        |> Enum.map(fn recipe ->
          recipe = FeedMe.Repo.preload(recipe, :ingredients)
          ingredient_names = Enum.map(recipe.ingredients, &String.downcase(&1.name))
          have = Enum.count(ingredient_names, &MapSet.member?(pantry_items, &1))
          missing = length(ingredient_names) - have
          {recipe, have, missing}
        end)
        |> Enum.filter(fn {_, _, missing} -> missing <= max_missing end)
        |> Enum.sort_by(fn {_, have, missing} -> {missing, -have} end)
        |> Enum.take(5)

      if scored == [] do
        {:ok, "No recipes found with #{max_missing} or fewer missing ingredients."}
      else
        result =
          scored
          |> Enum.map(fn {recipe, have, missing} ->
            "- #{recipe.title}: have #{have} ingredients, missing #{missing}"
          end)
          |> Enum.join("\n")

        {:ok, "Recipe suggestions based on your pantry:\n#{result}"}
      end
    end
  end

  defp execute_search_web(args, %{household_id: household_id}) do
    query = args["query"]

    if is_nil(query) or query == "" do
      {:error, "Search query is required"}
    else
      # Get the API key for this household
      case FeedMe.AI.get_api_key(household_id, "openrouter") do
        nil ->
          {:error, "No API key configured. Please set up an OpenRouter API key in settings."}

        api_key_record ->
          api_key = ApiKey.decrypt_key(api_key_record)

          # Call Perplexity Sonar via OpenRouter
          messages = [
            %{
              role: :system,
              content: "You are a helpful culinary assistant. Provide concise, accurate information about recipes, cooking techniques, and food. Include specific details like ingredients, measurements, and steps when relevant. Keep responses focused and practical."
            },
            %{
              role: :user,
              content: query
            }
          ]

          case OpenRouter.chat(api_key, messages, model: "perplexity/sonar") do
            {:ok, response} ->
              content = response.content || "No results found."
              {:ok, format_search_result(content, response.citations)}

            {:error, :invalid_api_key} ->
              {:error, "Invalid API key. Please check your OpenRouter API key in settings."}

            {:error, :rate_limited} ->
              {:error, "Rate limited. Please try again in a moment."}

            {:error, reason} ->
              {:error, "Web search failed: #{inspect(reason)}"}
          end
      end
    end
  end

  # Helpers

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp execute_add_recipe(args, %{household_id: household_id, user: user}) do
    # Build recipe attributes
    recipe_attrs = %{
      title: args["title"],
      description: args["description"],
      instructions: args["instructions"],
      prep_time_minutes: args["prep_time_minutes"],
      cook_time_minutes: args["cook_time_minutes"],
      servings: args["servings"],
      source_url: args["source_url"],
      source_name: args["source_name"],
      tags: args["tags"] || [],
      household_id: household_id,
      created_by_id: user.id
    }

    case Recipes.create_recipe(recipe_attrs) do
      {:ok, recipe} ->
        # Add ingredients if provided
        ingredients = args["ingredients"] || []

        if ingredients != [] do
          ingredient_list =
            Enum.map(ingredients, fn ing ->
              %{
                name: ing["name"],
                quantity: ing["quantity"] && Decimal.new("#{ing["quantity"]}"),
                unit: ing["unit"],
                notes: ing["notes"],
                optional: ing["optional"] || false
              }
            end)

          Recipes.bulk_create_ingredients(recipe.id, ingredient_list)
        end

        # Build confirmation message
        ingredient_count = length(ingredients)
        time_info = format_time_info(args["prep_time_minutes"], args["cook_time_minutes"])
        servings_info = if args["servings"], do: " • #{args["servings"]} servings", else: ""

        {:ok, "Added recipe \"#{recipe.title}\" with #{ingredient_count} ingredients#{time_info}#{servings_info}"}

      {:error, changeset} ->
        {:error, "Failed to add recipe: #{format_changeset_errors(changeset)}"}
    end
  end

  defp format_time_info(nil, nil), do: ""
  defp format_time_info(prep, nil), do: " • #{prep} min prep"
  defp format_time_info(nil, cook), do: " • #{cook} min cook"
  defp format_time_info(prep, cook), do: " • #{prep + cook} min total"

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_search_result(content, nil), do: content
  defp format_search_result(content, []), do: content

  defp format_search_result(content, citations) when is_list(citations) do
    # Format citations as a numbered list of sources
    sources =
      citations
      |> Enum.with_index(1)
      |> Enum.map(fn {url, idx} -> "[#{idx}] #{url}" end)
      |> Enum.join("\n")

    "#{content}\n\nSources:\n#{sources}"
  end
end
