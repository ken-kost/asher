defmodule Asher.Manifest do
  @moduledoc """
  Computes the repo manifest (`priv/repos.json`) and the managed `.gitignore`
  block of cloned repo directories as `{path, content}` changes. Igniter-free —
  the caller (a `mix asher.*` task or the `asher` escript) decides how to write
  them.
  """

  alias Asher.Repos

  @gitignore_path ".gitignore"
  @start_marker "# === asher: cloned org repos (managed; see priv/repos.json) ==="
  @end_marker "# === end asher clones ==="

  @doc """
  Merge freshly-synced `entries` for `org` into the on-disk manifest and compute
  the resulting file changes (igniter-free). Returns `{merged_manifest, changes}`
  where `changes` is a list of `{path, content}` for `priv/repos.json` and
  `.gitignore`. The caller decides how to write them (igniter or `Asher.FS`).
  """
  @spec changes(String.t(), [map()]) :: {[map()], [{Path.t(), String.t()}]}
  def changes(org, entries) do
    merged = Repos.merge(Repos.all(), org, entries)
    json = Jason.encode!(merged, pretty: true) <> "\n"

    {merged, [{"priv/repos.json", json}, {@gitignore_path, gitignore_content(merged)}]}
  end

  defp gitignore_content(manifest) do
    names = manifest |> Enum.map(& &1["name"]) |> Enum.uniq() |> Enum.sort()
    block = render_block(names)

    case File.read(@gitignore_path) do
      {:ok, existing} -> replace_block(existing, block)
      {:error, _} -> block
    end
  end

  @doc false
  def render_block(names) do
    lines = Enum.map_join(names, "\n", &"/#{&1}/")
    @start_marker <> "\n" <> lines <> "\n" <> @end_marker <> "\n"
  end

  @doc false
  def replace_block(existing, block) do
    if String.contains?(existing, @start_marker) do
      pattern = ~r/#{Regex.escape(@start_marker)}.*?#{Regex.escape(@end_marker)}\n?/s
      Regex.replace(pattern, existing, block)
    else
      String.trim_trailing(existing) <> "\n\n" <> block
    end
  end
end
