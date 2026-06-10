defmodule Asher.Survey do
  @moduledoc """
  The interactive contribution survey, shared by `mix asher.init` and `asher init`.

  Four steps: (1) optional issue link → scrape it, (2) category, (3) related
  repo(s) — a repeatable single-select loop, (4) name. Returns a plain map
  consumed by the caller. Uses `Asher.Console` for all prompts (no igniter / no
  `Mix.shell`), which keeps it usable from the escript and drivable from tests
  via `ExUnit.CaptureIO`.
  """

  alias Asher.{Console, Contribution, Github}

  @doc "Run the survey against the tracked `repos`, returning the answers map."
  @spec run([map()]) :: map()
  def run(repos) do
    {issue, scraped} = ask_issue()
    category = ask_category(derive_category(scraped))
    selected = select_repos(repos, prefill(repos, issue))
    {name, slug} = ask_name(scraped, category)

    %{issue: issue, scraped: scraped, category: category, repos: selected, name: name, slug: slug}
  end

  # --- Step 1: issue ---------------------------------------------------------

  defp ask_issue do
    if Console.yes?("Does this contribution have an issue?") do
      case Github.parse_issue_ref(prompt("Paste the issue URL (or org/repo#123)")) do
        {:ok, %{org: org, repo: repo, number: number}} ->
          scrape(org, repo, number)

        {:error, msg} ->
          Console.warn("  #{msg}; continuing without an issue.")
          {nil, nil}
      end
    else
      {nil, nil}
    end
  end

  defp scrape(org, repo, number) do
    issue = %{org: org, repo: repo, full_name: "#{org}/#{repo}", number: number, url: nil}

    case Github.view_issue(org, repo, number) do
      {:ok, data} ->
        Console.say("  Scraped: #{data["title"]}  [#{Enum.join(data["labels"], ", ")}]")
        {%{issue | url: data["url"]}, data}

      {:error, msg} ->
        Console.warn("  Could not scrape issue (#{msg}); continuing with the link only.")
        {issue, nil}
    end
  end

  @doc false
  # label → category heuristics, used to pre-select a default
  def derive_category(nil), do: nil

  def derive_category(%{"labels" => labels}) do
    labels = Enum.map(labels, &String.downcase/1)

    cond do
      Enum.any?(labels, &(&1 in ["bug", "kind:bug", "type:bug"])) ->
        "fix"

      Enum.any?(labels, &String.contains?(&1, "enhancement")) ->
        "enhancement"

      Enum.any?(labels, &(String.contains?(&1, "documentation") or String.contains?(&1, "docs"))) ->
        "documentation"

      Enum.any?(labels, &(&1 in ["test", "tests", "testing"])) ->
        "test"

      Enum.any?(labels, &String.contains?(&1, "feature")) ->
        "feature"

      Enum.any?(labels, &String.contains?(&1, "improvement")) ->
        "improvement"

      true ->
        nil
    end
  end

  def derive_category(_), do: nil

  # --- Step 2: category ------------------------------------------------------

  defp ask_category(default) do
    case Console.select(
           "What kind of contribution is this?",
           Contribution.categories() ++ [:other],
           default: default,
           display: &category_display/1
         ) do
      :other -> ask_custom_category()
      category -> category
    end
  end

  defp ask_custom_category do
    case prompt("Enter your category (used as the commit/branch prefix, e.g. perf, chore)") do
      "" ->
        Console.say("  A category is required.")
        ask_custom_category()

      custom ->
        custom
    end
  end

  defp category_display(:other), do: "other (enter your own)"
  defp category_display(category), do: category

  # --- Step 3: repos (repeatable single-select until :done) ------------------

  defp prefill(repos, %{full_name: full_name}),
    do: Enum.filter(repos, &(&1["full_name"] == full_name))

  defp prefill(_repos, _), do: []

  defp select_repos(all_repos, prefilled), do: do_select_repos(all_repos, prefilled)

  defp do_select_repos(all_repos, acc) do
    remaining = Enum.reject(all_repos, &(&1 in acc))
    label = if acc == [], do: "(none yet)", else: Enum.map_join(acc, ", ", & &1["full_name"])

    # Always include the :done sentinel so the menu never collapses to a single
    # auto-returned item while repos remain to choose from.
    choice =
      Console.select(
        "Add a related repo — selected: #{label}. Pick 'done' to finish.",
        [:done | remaining],
        display: &repo_display/1
      )

    case choice do
      :done when acc == [] ->
        Console.say("  Please select at least one repo.")
        do_select_repos(all_repos, acc)

      :done ->
        acc

      repo ->
        do_select_repos(all_repos, acc ++ [repo])
    end
  end

  defp repo_display(:done), do: "✓ done"
  defp repo_display(repo), do: "#{repo["full_name"]} — #{repo["description"]}"

  # --- Step 4: name ----------------------------------------------------------

  defp ask_name(scraped, category) do
    suggested = (scraped && scraped["title"]) || "#{category} contribution"

    name =
      case prompt("Name this contribution [#{suggested}]") do
        "" -> suggested
        input -> input
      end

    {name, Contribution.slugify(name)}
  end

  defp prompt(message), do: Console.prompt(message <> " ❯ ")
end
