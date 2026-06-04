defmodule Asher.Contributions do
  @moduledoc """
  Load and update the contribution receipts under `data/`. Used by `push` and
  `status` to find a prepared contribution and update it once published.
  """

  alias Asher.Workspace

  @type t :: %{path: Path.t(), dir: Path.t(), meta: map()}

  @doc "All contributions on disk, sorted by folder, as `%{path, dir, meta}`."
  @spec list() :: [t()]
  def list do
    [Workspace.data_root(), "*", "contribution.json"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      case load(path) do
        {:ok, meta} -> [%{path: path, dir: Path.dirname(path), meta: meta}]
        :error -> []
      end
    end)
  end

  @doc "Find a contribution by exact slug, or by folder-name substring."
  @spec find(String.t()) :: t() | nil
  def find(slug) do
    Enum.find(list(), fn c -> c.meta["slug"] == slug or String.contains?(c.dir, slug) end)
  end

  @doc """
  Reconstruct a survey-shaped map from a receipt's metadata, so PR title/body can
  be recomputed at push time.
  """
  @spec to_survey(map()) :: map()
  def to_survey(meta) do
    %{
      name: meta["name"],
      slug: meta["slug"],
      category: meta["category"],
      repos:
        Enum.map(meta["repos"], fn r ->
          %{
            "org" => r["org"],
            "name" => r["name"],
            "full_name" => r["full_name"],
            "description" => r["description"] || ""
          }
        end),
      issue: to_issue(meta["issue"]),
      scraped: meta["scraped"]
    }
  end

  @doc "Merge `info` into the `repos[]` entry matching `full_name`."
  @spec put_repo(map(), String.t(), map()) :: map()
  def put_repo(meta, full_name, info) do
    repos =
      Enum.map(meta["repos"], fn r ->
        if r["full_name"] == full_name, do: Map.merge(r, info), else: r
      end)

    Map.put(meta, "repos", repos)
  end

  defp load(path) do
    with {:ok, json} <- File.read(path),
         {:ok, meta} <- Jason.decode(json) do
      {:ok, meta}
    else
      _ -> :error
    end
  end

  defp to_issue(nil), do: nil

  defp to_issue(m) do
    %{
      org: m["org"],
      repo: m["repo"],
      full_name: m["full_name"],
      number: m["number"],
      url: m["url"]
    }
  end
end
