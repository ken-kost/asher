defmodule Asher.Contribution do
  @moduledoc """
  Pure helpers describing a contribution: the category taxonomy, slug/branch/
  folder naming, and the metadata receipt written under `data/`.
  """

  @categories ["feature", "enhancement", "bug fix", "improvement", "documentation"]

  @prefixes %{
    "feature" => "feat",
    "enhancement" => "enhance",
    "bug fix" => "fix",
    "improvement" => "improve",
    "documentation" => "docs"
  }

  @doc "The selectable contribution categories, in display order."
  @spec categories() :: [String.t()]
  def categories, do: @categories

  @doc "Git branch prefix for a category (defaults to `feat` for unknowns)."
  @spec category_prefix(String.t()) :: String.t()
  def category_prefix(category), do: Map.get(@prefixes, category, "feat")

  @doc "Branch name for a contribution, e.g. `fix/add-upsert-support`."
  @spec branch_name(String.t(), String.t()) :: String.t()
  def branch_name(category, slug), do: "#{category_prefix(category)}/#{slug}"

  @doc """
  Turn arbitrary text into a git/url-friendly slug.

  Lowercases, replaces any run of non `[a-z0-9]` characters with a single
  hyphen, trims hyphens, and caps the length. Empty results fall back to
  `"contribution"`.
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(text) do
    slug =
      text
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 60)
      |> String.trim("-")

    if slug == "", do: "contribution", else: slug
  end

  @doc ~S"""
  The `data/` folder name for a contribution: `"<slug> (<repo1>, <repo2>)"`.

  Pass slash-free repo *names* (not `org/name` full names) so the folder stays a
  single directory level.
  """
  @spec folder_name(String.t(), [String.t()]) :: String.t()
  def folder_name(slug, repo_names), do: "#{slug} (#{Enum.join(repo_names, ", ")})"

  @doc """
  Build the machine-readable metadata map for a contribution receipt.

  `results` maps a repo's `full_name` to a map with at least `:status` and,
  for successes, `:pr_url`.
  """
  @spec metadata_map(map(), String.t() | nil, map(), boolean()) :: map()
  def metadata_map(survey, owner, results, dry_run) do
    %{
      "name" => survey.name,
      "slug" => survey.slug,
      "category" => survey.category,
      "branch" => branch_name(survey.category, survey.slug),
      "fork_owner" => owner,
      "dry_run" => dry_run,
      "repos" =>
        Enum.map(survey.repos, fn r ->
          %{"org" => r["org"], "name" => r["name"], "full_name" => r["full_name"]}
        end),
      "issue" => issue_map(survey.issue),
      "scraped" => scraped_map(survey.scraped),
      "results" => stringify_results(results),
      "created_at" => timestamp()
    }
  end

  @doc """
  The receipt file changes for a contribution: `[{path, content}]` for
  `contribution.json` and `contribution.md` under `data/<folder>/`. The caller
  writes them (igniter or `Asher.FS`).
  """
  @spec receipt_files(map(), String.t() | nil, map(), boolean()) :: [{Path.t(), String.t()}]
  def receipt_files(survey, owner, results, dry_run) do
    meta = metadata_map(survey, owner, results, dry_run)
    folder = folder_name(survey.slug, Enum.map(survey.repos, & &1["name"]))
    dir = Path.join("data", folder)

    [
      {Path.join(dir, "contribution.json"), Jason.encode!(meta, pretty: true) <> "\n"},
      {Path.join(dir, "contribution.md"), render_markdown(meta)}
    ]
  end

  @doc "Render a human-readable Markdown receipt from the metadata map."
  @spec render_markdown(map()) :: String.t()
  def render_markdown(meta) do
    issue_line =
      case meta["issue"] do
        nil -> "_No linked issue._"
        %{"url" => url} when is_binary(url) -> "[#{url}](#{url})"
        %{"full_name" => fname, "number" => n} -> "#{fname}##{n}"
      end

    labels =
      case meta["scraped"] do
        %{"labels" => labels} when labels != [] -> Enum.join(labels, ", ")
        _ -> "—"
      end

    rows =
      Enum.map_join(meta["results"], "\n", fn {full, r} ->
        link =
          case r do
            %{"pr_url" => url} when is_binary(url) -> "[#{url}](#{url})"
            %{"status" => "error", "error" => e} -> "❌ #{e}"
            _ -> "—"
          end

        "| `#{full}` | #{link} |"
      end)

    rows = if rows == "", do: "| _none_ | _none_ |", else: rows

    """
    # #{meta["name"]}#{if meta["dry_run"], do: " _(dry run)_", else: ""}

    - **Category:** #{meta["category"]}
    - **Branch:** `#{meta["branch"]}`
    - **Fork owner:** #{meta["fork_owner"] || "—"}
    - **Issue:** #{issue_line}
    - **Scraped labels:** #{labels}
    - **Created:** #{meta["created_at"]}

    ## Pull requests

    | Repo | PR |
    | ---- | -- |
    #{rows}
    """
  end

  defp issue_map(nil), do: nil

  defp issue_map(issue) do
    %{
      "org" => issue.org,
      "repo" => issue.repo,
      "full_name" => issue.full_name,
      "number" => issue.number,
      "url" => issue.url
    }
  end

  defp scraped_map(nil), do: nil

  defp scraped_map(scraped) do
    %{
      "title" => scraped["title"],
      "labels" => scraped["labels"] || [],
      "state" => scraped["state"]
    }
  end

  defp stringify_results(results) do
    Map.new(results, fn {full, r} ->
      {full, Map.new(r, fn {k, v} -> {to_string(k), v} end)}
    end)
  end

  # Wrapped so tests can run without a clock dependency; DateTime is fine here
  # (this is library code, not a Workflow script).
  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
