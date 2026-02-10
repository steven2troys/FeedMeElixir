defmodule FeedMe.AI.Tools do
  @moduledoc """
  AI tool definitions and execution for FeedMe assistant.
  """

  alias FeedMe.{MealPlanning, Pantry, Procurement, Profiles, Recipes, Shopping, Suppliers}
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
      add_recipe(),
      estimate_nutrition(),
      suggest_meal_plan(),
      create_procurement_plan(),
      sync_procurement_to_shopping_list(),
      get_supplier_link()
    ]
  end

  @doc """
  Executes a tool call and returns the result.
  """
  def execute(tool_name, args, context) do
    case tool_name do
      "add_to_pantry" ->
        execute_add_to_pantry(args, context)

      "add_to_shopping_list" ->
        execute_add_to_shopping_list(args, context)

      "search_recipes" ->
        execute_search_recipes(args, context)

      "get_taste_profiles" ->
        execute_get_taste_profiles(args, context)

      "check_pantry" ->
        execute_check_pantry(args, context)

      "get_pantry_categories" ->
        execute_get_pantry_categories(args, context)

      "suggest_recipe" ->
        execute_suggest_recipe(args, context)

      "search_web" ->
        execute_search_web(args, context)

      "add_recipe" ->
        execute_add_recipe(args, context)

      "estimate_nutrition" ->
        execute_estimate_nutrition(args, context)

      "suggest_meal_plan" ->
        execute_suggest_meal_plan(args, context)

      "create_procurement_plan" ->
        execute_create_procurement_plan(args, context)

      "sync_procurement_to_shopping_list" ->
        execute_sync_procurement_to_shopping_list(args, context)

      "get_supplier_link" ->
        execute_get_supplier_link(args, context)

      _ ->
        {:error, "Unknown tool: #{tool_name}"}
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
            unit: %{
              type: "string",
              description: "Unit of measurement (e.g., 'lbs', 'oz', 'cups')"
            },
            category: %{type: "string", description: "Category name (e.g., 'Produce', 'Dairy')"},
            shelf_life_days: %{
              type: "integer",
              description:
                "Estimated shelf life in days from today. Always provide this. Examples: bananas=5, bread=7, milk=10, eggs=21, chicken=2, canned goods=730, fresh herbs=7, cheese=30."
            },
            nutrition: %{
              type: "object",
              description: "Estimated nutritional information per serving",
              properties: %{
                calories: %{type: "number", description: "Calories per serving"},
                protein_g: %{type: "number", description: "Protein in grams"},
                carbs_g: %{type: "number", description: "Carbohydrates in grams"},
                fat_g: %{type: "number", description: "Fat in grams"},
                fiber_g: %{type: "number", description: "Fiber in grams"},
                sugar_g: %{type: "number", description: "Sugar in grams"},
                sodium_mg: %{type: "number", description: "Sodium in milligrams"},
                serving_size: %{
                  type: "string",
                  description: "Serving size description (e.g., '100g', '1 cup', '1 medium')"
                }
              }
            }
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
            tag: %{
              type: "string",
              description: "Filter by tag (e.g., 'dinner', 'quick', 'vegetarian')"
            },
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
        description:
          "Get the household's taste profile including dietary restrictions, allergies, and preferences",
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
            low_stock_only: %{
              type: "boolean",
              description: "Only return items that need restocking"
            }
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
            use_pantry_items: %{
              type: "boolean",
              description: "Prioritize recipes using pantry items"
            },
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
        description:
          "Search the web for recipes, cooking techniques, ingredient substitutions, food information, or any other culinary knowledge not in the household's recipe book",
        parameters: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description:
                "The search query - be specific and include relevant context (e.g., 'authentic Italian carbonara recipe' or 'substitute for buttermilk in baking')"
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
        description:
          "Add a new recipe to the household's recipe book. Use this when the user wants to save a recipe you found or know from your training.",
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
                  unit: %{
                    type: "string",
                    description: "Unit of measurement (e.g., 'cups', 'tbsp', 'oz')"
                  },
                  notes: %{
                    type: "string",
                    description: "Optional notes (e.g., 'diced', 'room temperature')"
                  },
                  optional: %{type: "boolean", description: "Whether this ingredient is optional"},
                  nutrition: %{
                    type: "object",
                    description: "Estimated nutritional info for this ingredient amount",
                    properties: %{
                      calories: %{type: "number", description: "Calories"},
                      protein_g: %{type: "number", description: "Protein in grams"},
                      carbs_g: %{type: "number", description: "Carbohydrates in grams"},
                      fat_g: %{type: "number", description: "Fat in grams"},
                      fiber_g: %{type: "number", description: "Fiber in grams"},
                      sugar_g: %{type: "number", description: "Sugar in grams"},
                      sodium_mg: %{type: "number", description: "Sodium in milligrams"},
                      serving_size: %{type: "string", description: "Serving size"}
                    }
                  }
                },
                required: ["name"]
              }
            },
            prep_time_minutes: %{type: "integer", description: "Preparation time in minutes"},
            cook_time_minutes: %{type: "integer", description: "Cooking time in minutes"},
            servings: %{type: "integer", description: "Number of servings"},
            source_url: %{
              type: "string",
              description: "URL where the recipe was found (if applicable)"
            },
            source_name: %{
              type: "string",
              description:
                "Name of the source (e.g., 'New York Times Cooking', 'Grandma's cookbook')"
            },
            tags: %{
              type: "array",
              items: %{type: "string"},
              description:
                "Tags for categorization (e.g., 'dinner', 'vegetarian', 'quick', 'italian')"
            }
          },
          required: ["title", "instructions", "ingredients"]
        }
      }
    }
  end

  defp estimate_nutrition do
    %{
      type: "function",
      function: %{
        name: "estimate_nutrition",
        description:
          "Estimate and save nutritional information for an existing pantry item or recipe ingredient",
        parameters: %{
          type: "object",
          properties: %{
            item_id: %{
              type: "string",
              description: "ID of the pantry item to estimate nutrition for"
            },
            ingredient_id: %{
              type: "string",
              description: "ID of the recipe ingredient to estimate nutrition for"
            },
            nutrition: %{
              type: "object",
              description: "The estimated nutritional information",
              properties: %{
                calories: %{type: "number", description: "Calories per serving"},
                protein_g: %{type: "number", description: "Protein in grams"},
                carbs_g: %{type: "number", description: "Carbohydrates in grams"},
                fat_g: %{type: "number", description: "Fat in grams"},
                fiber_g: %{type: "number", description: "Fiber in grams"},
                sugar_g: %{type: "number", description: "Sugar in grams"},
                sodium_mg: %{type: "number", description: "Sodium in milligrams"},
                serving_size: %{type: "string", description: "Serving size description"}
              },
              required: ["calories", "protein_g", "carbs_g", "fat_g"]
            }
          },
          required: ["nutrition"]
        }
      }
    }
  end

  defp suggest_meal_plan do
    %{
      type: "function",
      function: %{
        name: "suggest_meal_plan",
        description:
          "Create an AI-suggested meal plan for a date range. Uses household recipes, pantry stock, taste profiles, and cooking history to generate a balanced plan.",
        parameters: %{
          type: "object",
          properties: %{
            start_date: %{
              type: "string",
              description: "Start date in YYYY-MM-DD format"
            },
            end_date: %{
              type: "string",
              description: "End date in YYYY-MM-DD format"
            },
            meals_per_day: %{
              type: "array",
              items: %{type: "string", enum: ["breakfast", "lunch", "dinner", "snack"]},
              description:
                "Which meals to plan for each day. Defaults to [\"breakfast\", \"lunch\", \"dinner\"]"
            },
            prefer_pantry_items: %{
              type: "boolean",
              description: "Prioritize recipes that use items already in the pantry"
            },
            servings: %{
              type: "integer",
              description: "Default servings per meal"
            }
          },
          required: ["start_date", "end_date"]
        }
      }
    }
  end

  defp create_procurement_plan do
    %{
      type: "function",
      function: %{
        name: "create_procurement_plan",
        description:
          "Create a procurement plan from a meal plan, restock needs, or expiring items. Aggregates needs, subtracts pantry stock, assigns default supplier, and generates shopping links.",
        parameters: %{
          type: "object",
          properties: %{
            meal_plan_id: %{
              type: "string",
              description: "ID of the meal plan to create procurement from (optional)"
            },
            include_restock: %{
              type: "boolean",
              description: "Include items needing restock"
            },
            include_expiring: %{
              type: "boolean",
              description: "Include items expiring soon"
            }
          }
        }
      }
    }
  end

  defp sync_procurement_to_shopping_list do
    %{
      type: "function",
      function: %{
        name: "sync_procurement_to_shopping_list",
        description: "Add approved procurement plan items to the main shopping list",
        parameters: %{
          type: "object",
          properties: %{
            procurement_plan_id: %{
              type: "string",
              description: "ID of the procurement plan to sync"
            }
          },
          required: ["procurement_plan_id"]
        }
      }
    }
  end

  defp get_supplier_link do
    %{
      type: "function",
      function: %{
        name: "get_supplier_link",
        description: "Generate a deep-link URL to search for a product on a supplier's website",
        parameters: %{
          type: "object",
          properties: %{
            product_name: %{
              type: "string",
              description: "Name of the product to search for"
            },
            supplier_id: %{
              type: "string",
              description: "ID of the supplier (uses household default if not provided)"
            }
          },
          required: ["product_name"]
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

    today = today_for_household(household_id)

    expiration_date =
      case args["shelf_life_days"] do
        days when is_integer(days) and days > 0 ->
          Date.add(today, days)

        days when is_float(days) and days > 0 ->
          Date.add(today, round(days))

        days when is_binary(days) ->
          case Integer.parse(days) do
            {d, _} when d > 0 -> Date.add(today, d)
            _ -> nil
          end

        _ ->
          nil
      end

    attrs = %{
      name: args["name"],
      quantity: args["quantity"] && Decimal.new("#{args["quantity"]}"),
      unit: args["unit"],
      category_id: category_id,
      household_id: household_id,
      expiration_date: expiration_date
    }

    case Pantry.create_item(attrs, user) do
      {:ok, item} ->
        # Add nutrition if provided
        if args["nutrition"] do
          nutrition = build_nutrition_attrs(args["nutrition"])
          Pantry.update_item_nutrition(item, nutrition)
        end

        result =
          "Added #{item.name} to pantry" <>
            if(item.quantity, do: " (#{item.quantity} #{item.unit || "units"})", else: "")

        result =
          if item.expiration_date do
            result <> ", expires #{item.expiration_date}"
          else
            result
          end

        {:ok, result}

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

        {:ok,
         "Taste Profile Summary: #{summary}#{restrictions}#{allergies}#{dislikes}#{favorites}"}

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
          qty =
            if item.quantity,
              do: " (#{Decimal.to_string(item.quantity)} #{item.unit || ""})",
              else: ""

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
              content:
                "You are a helpful culinary assistant. Provide concise, accurate information about recipes, cooking techniques, and food. Include specific details like ingredients, measurements, and steps when relevant. Keep responses focused and practical."
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

  defp execute_estimate_nutrition(args, %{household_id: household_id}) do
    nutrition = build_nutrition_attrs(args["nutrition"])

    cond do
      args["item_id"] ->
        case Pantry.get_item(args["item_id"], household_id) do
          nil ->
            {:error, "Pantry item not found"}

          item ->
            case Pantry.update_item_nutrition(item, nutrition) do
              {:ok, _} -> {:ok, "Nutrition estimated for #{item.name}"}
              {:error, cs} -> {:error, "Failed: #{inspect(cs.errors)}"}
            end
        end

      args["ingredient_id"] ->
        case Recipes.get_ingredient(args["ingredient_id"]) do
          nil ->
            {:error, "Ingredient not found"}

          ingredient ->
            case Recipes.update_ingredient_nutrition(ingredient, nutrition) do
              {:ok, _} -> {:ok, "Nutrition estimated for #{ingredient.name}"}
              {:error, cs} -> {:error, "Failed: #{inspect(cs.errors)}"}
            end
        end

      true ->
        {:error, "Either item_id or ingredient_id is required"}
    end
  end

  defp execute_create_procurement_plan(args, %{household_id: household_id, user: user}) do
    results = []

    results =
      if args["meal_plan_id"] do
        case MealPlanning.get_meal_plan(args["meal_plan_id"], household_id) do
          nil ->
            [{:error, "Meal plan not found"} | results]

          meal_plan ->
            case Procurement.create_from_meal_plan(meal_plan, user) do
              {:ok, :no_needs} ->
                [{:ok, "No shopping needs for this meal plan"} | results]

              {:ok, plan} ->
                [{:ok, "Created procurement plan \"#{plan.name}\" from meal plan"} | results]

              {:error, _} ->
                [{:error, "Failed to create from meal plan"} | results]
            end
        end
      else
        results
      end

    results =
      if args["include_restock"] do
        case Procurement.create_from_restock(household_id, user) do
          {:ok, :no_needs} -> [{:ok, "No items need restocking"} | results]
          {:ok, plan} -> [{:ok, "Created restock plan \"#{plan.name}\""} | results]
          {:error, _} -> [{:error, "Failed to create restock plan"} | results]
        end
      else
        results
      end

    results =
      if args["include_expiring"] do
        case Procurement.create_from_expiring(household_id, user) do
          {:ok, :no_needs} -> [{:ok, "No items expiring soon"} | results]
          {:ok, plan} -> [{:ok, "Created expiring items plan \"#{plan.name}\""} | results]
          {:error, _} -> [{:error, "Failed to create expiring items plan"} | results]
        end
      else
        results
      end

    if results == [] do
      {:error,
       "No procurement source specified. Provide meal_plan_id, include_restock, or include_expiring."}
    else
      messages =
        results
        |> Enum.reverse()
        |> Enum.map(fn
          {:ok, msg} -> msg
          {:error, msg} -> "Error: #{msg}"
        end)
        |> Enum.join("\n")

      {:ok, messages}
    end
  end

  defp execute_sync_procurement_to_shopping_list(args, %{household_id: household_id, user: user}) do
    case Procurement.get_plan(args["procurement_plan_id"], household_id) do
      nil ->
        {:error, "Procurement plan not found"}

      plan ->
        case Procurement.sync_to_shopping_list(plan, user) do
          {:ok, %{added: added}} ->
            {:ok, "Added #{added} items from procurement plan to shopping list"}
        end
    end
  end

  defp execute_get_supplier_link(args, %{household_id: household_id}) do
    product_name = args["product_name"]

    supplier =
      if args["supplier_id"] do
        Suppliers.get_supplier(args["supplier_id"])
      else
        hs = Suppliers.get_default_supplier(household_id)
        hs && FeedMe.Repo.preload(hs, :supplier).supplier
      end

    case supplier do
      nil ->
        {:error, "No supplier found. Enable a supplier in Settings > Suppliers."}

      supplier ->
        case Suppliers.generate_deep_link(supplier, product_name) do
          nil ->
            {:ok,
             "#{supplier.name} doesn't have a search URL configured. Visit #{supplier.website_url || supplier.name} to search for \"#{product_name}\"."}

          url ->
            {:ok, "Search for \"#{product_name}\" on #{supplier.name}: #{url}"}
        end
    end
  end

  defp execute_suggest_meal_plan(args, %{household_id: household_id, user: user}) do
    start_date = Date.from_iso8601!(args["start_date"])
    end_date = Date.from_iso8601!(args["end_date"])
    meals = args["meals_per_day"] || ["breakfast", "lunch", "dinner"]
    servings = args["servings"]

    # Get household recipes
    recipes = Recipes.list_recipes(household_id)

    if recipes == [] do
      {:error,
       "No recipes in your recipe book yet. Add some recipes first to generate a meal plan."}
    else
      plan_name = "Week of #{Calendar.strftime(start_date, "%b %d")}"

      case MealPlanning.create_meal_plan(%{
             name: plan_name,
             start_date: start_date,
             end_date: end_date,
             household_id: household_id,
             created_by_id: user.id,
             ai_generated: true,
             status: :draft
           }) do
        {:ok, meal_plan} ->
          # Distribute recipes across days and meal types
          dates = Date.range(start_date, end_date) |> Enum.to_list()
          shuffled_recipes = Enum.shuffle(recipes)
          recipe_cycle = Stream.cycle(shuffled_recipes)

          items =
            for {date, day_idx} <- Enum.with_index(dates),
                {meal_type, meal_idx} <- Enum.with_index(meals) do
              idx = day_idx * length(meals) + meal_idx
              recipe = Enum.at(recipe_cycle, idx)

              %{
                date: date,
                meal_type: meal_type,
                title: recipe.title,
                servings: servings || recipe.servings,
                meal_plan_id: meal_plan.id,
                recipe_id: recipe.id,
                assigned_by_id: user.id
              }
            end

          Enum.each(items, &MealPlanning.create_item/1)

          total_items = length(items)
          total_days = length(dates)

          {:ok,
           "Created draft meal plan \"#{plan_name}\" with #{total_items} meals across #{total_days} days. " <>
             "Review and modify the plan at the Meal Plans page, then activate it when ready."}

        {:error, changeset} ->
          {:error, "Failed to create meal plan: #{format_changeset_errors(changeset)}"}
      end
    end
  end

  # Helpers

  @doc false
  def build_nutrition_attrs(nil), do: %{}

  def build_nutrition_attrs(nutrition) when is_map(nutrition) do
    %{
      calories: nutrition["calories"] && Decimal.new("#{nutrition["calories"]}"),
      protein_g: nutrition["protein_g"] && Decimal.new("#{nutrition["protein_g"]}"),
      carbs_g: nutrition["carbs_g"] && Decimal.new("#{nutrition["carbs_g"]}"),
      fat_g: nutrition["fat_g"] && Decimal.new("#{nutrition["fat_g"]}"),
      fiber_g: nutrition["fiber_g"] && Decimal.new("#{nutrition["fiber_g"]}"),
      sugar_g: nutrition["sugar_g"] && Decimal.new("#{nutrition["sugar_g"]}"),
      sodium_mg: nutrition["sodium_mg"] && Decimal.new("#{nutrition["sodium_mg"]}"),
      serving_size: nutrition["serving_size"],
      source: "ai_estimated"
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp today_for_household(household_id) do
    household = FeedMe.Households.get_household(household_id)
    tz = (household && household.timezone) || "America/Los_Angeles"

    case DateTime.now(tz) do
      {:ok, dt} -> DateTime.to_date(dt)
      _ -> Date.utc_today()
    end
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

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
              base = %{
                name: ing["name"],
                quantity: ing["quantity"] && Decimal.new("#{ing["quantity"]}"),
                unit: ing["unit"],
                notes: ing["notes"],
                optional: ing["optional"] || false
              }

              if ing["nutrition"] do
                Map.put(base, :nutrition, build_nutrition_attrs(ing["nutrition"]))
              else
                base
              end
            end)

          Recipes.bulk_create_ingredients(recipe.id, ingredient_list)
        end

        # Build confirmation message
        ingredient_count = length(ingredients)
        time_info = format_time_info(args["prep_time_minutes"], args["cook_time_minutes"])
        servings_info = if args["servings"], do: " • #{args["servings"]} servings", else: ""

        {:ok,
         "Added recipe \"#{recipe.title}\" with #{ingredient_count} ingredients#{time_info}#{servings_info}"}

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
