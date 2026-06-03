defmodule Asher.Repos do
  @moduledoc """
  Load, filter, and query the tracked-repo manifest (`priv/repos.json`).

  The manifest is a flat list of maps, one per repo, possibly spanning several
  GitHub orgs. This module is pure data plumbing — fetching from GitHub lives in
  `Asher.Github` and writing the manifest lives in `Asher.Manifest`.
  """

  alias Asher.Workspace

  @doc """
  All tracked repos from the per-workspace manifest (`<cwd>/priv/repos.json`).

  Returns `[]` when it does not exist yet — run `asher setup <org>` (or
  `mix asher.setup <org>`) to create it.
  """
  @spec all() :: [map()]
  def all do
    case File.read(Workspace.manifest_path()) do
      {:ok, json} -> Jason.decode!(json)
      {:error, _} -> []
    end
  end

  @doc "Tracked repo names."
  @spec names() :: [String.t()]
  def names, do: Enum.map(all(), & &1["name"])

  @doc "Find a tracked repo by name."
  @spec fetch(String.t()) :: map() | nil
  def fetch(name), do: Enum.find(all(), &(&1["name"] == name))

  @doc "Find a tracked repo by name or raise a helpful error."
  @spec fetch!(String.t()) :: map()
  def fetch!(name) do
    fetch(name) ||
      raise "Unknown repo #{inspect(name)}. Run `mix asher.setup <org>` to track it first."
  end

  @doc """
  Whether a raw GitHub API repo should be tracked, given filter `opts`:

    * `:lang` — keep only repos whose primary language matches (case-insensitive)
    * `:include` — names to keep regardless of other rules
    * `:exclude` — names to drop regardless of other rules

  Archived repos, forks, and `.github` are always excluded (unless force-included).
  """
  @spec keep?(map(), keyword() | map()) :: boolean()
  def keep?(repo, opts) do
    name = repo["name"]
    lang = opt(opts, :lang)
    include = opt(opts, :include) || []
    exclude = opt(opts, :exclude) || []

    cond do
      name in exclude -> false
      name in include -> true
      repo["archived"] == true -> false
      repo["fork"] == true -> false
      name == ".github" -> false
      is_nil(lang) -> true
      true -> lang_match?(repo["language"], lang)
    end
  end

  @doc "Filter raw GitHub API repos and normalize them into manifest entries."
  @spec filter([map()], String.t(), keyword() | map()) :: [map()]
  def filter(raw, org, opts) do
    raw
    |> Enum.filter(&keep?(&1, opts))
    |> Enum.map(&to_entry(&1, org))
    |> Enum.sort_by(& &1["name"])
  end

  @doc """
  Merge freshly-synced entries for `org` into the existing manifest, replacing
  any prior entries for that org and sorting by `full_name`.
  """
  @spec merge([map()], String.t(), [map()]) :: [map()]
  def merge(existing, org, new_entries) do
    existing
    |> Enum.reject(&(&1["org"] == org))
    |> Kernel.++(new_entries)
    |> Enum.sort_by(& &1["full_name"])
  end

  defp to_entry(repo, org) do
    %{
      "org" => org,
      "name" => repo["name"],
      "full_name" => "#{org}/#{repo["name"]}",
      "url" => repo["html_url"],
      "clone_url" => repo["clone_url"],
      "description" => repo["description"],
      "language" => repo["language"],
      "archived" => repo["archived"] || false,
      "fork" => repo["fork"] || false
    }
  end

  defp lang_match?(nil, _lang), do: false
  defp lang_match?(language, lang), do: String.downcase(language) == String.downcase(lang)

  defp opt(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp opt(opts, key) when is_map(opts), do: Map.get(opts, key)
end
