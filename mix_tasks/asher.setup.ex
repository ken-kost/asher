defmodule Mix.Tasks.Asher.Setup do
  use Igniter.Mix.Task

  alias Asher.{Git, Github, Manifest, Repos, Tasks}

  @example "mix asher.setup ash-project"

  @shortdoc "Sync a GitHub org and clone its repos into the workspace"
  @moduledoc """
  #{@shortdoc}

  The "set me up" command: point it at an org and it syncs that org's active
  repos into `priv/repos.json` (see `mix asher.repos.sync`) and then clones them
  into the workspace root as full, independent git repos so you can `cd` in and
  contribute. Cloning is idempotent — already-cloned repos are skipped. The
  clones are gitignored.

  ## Example

  ```sh
  #{@example}
  mix asher.setup ash-project ash ash_postgres   # only clone a subset
  mix asher.setup ash-project --lang elixir       # only track/clone Elixir repos
  mix asher.setup ash-project --no-clone          # sync the manifest only
  ```

  ## Arguments

  * `org` - org slug or URL. Defaults to `ash-project`.
  * `repos` - optional list of repo names to clone (default: all tracked for the org).

  ## Options

  * `--lang` / `-l` - keep only repos whose primary language matches
  * `--include` / `--exclude` - comma-separated overrides to the active-repo filter
  * `--no-clone` - sync the manifest but do not clone anything
  """

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :asher,
      example: @example,
      positional: [{:org, optional: true}, {:repos, optional: true, rest: true}],
      schema: [lang: :string, include: :string, exclude: :string, no_clone: :boolean],
      aliases: [l: :lang]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    org = Github.parse_org(igniter.args.positional[:org])
    opts = Tasks.parse_filter_opts(igniter.args.options)

    case Github.fetch_org_repos(org) do
      {:ok, raw} ->
        entries = Repos.filter(raw, org, opts)
        {_merged, changes} = Manifest.changes(org, entries)
        igniter = Asher.IgniterWrites.write(igniter, changes)

        igniter
        |> Igniter.add_notice("Synced #{length(entries)} repos from #{org}.")
        |> maybe_clone(entries, igniter.args.positional[:repos], igniter.args.options[:no_clone])

      {:error, msg} ->
        Igniter.add_issue(igniter, "asher.setup failed: #{msg}")
    end
  end

  defp maybe_clone(igniter, _entries, _filter, true) do
    Igniter.add_notice(igniter, "Skipped cloning (--no-clone).")
  end

  defp maybe_clone(igniter, entries, filter, _no_clone) do
    entries
    |> select(filter)
    |> Enum.reduce(igniter, &clone_one/2)
  end

  defp select(entries, nil), do: entries
  defp select(entries, []), do: entries
  defp select(entries, names), do: Enum.filter(entries, &(&1["name"] in names))

  defp clone_one(entry, igniter) do
    name = entry["name"]

    cond do
      Git.cloned?(name) ->
        Igniter.add_notice(igniter, "#{name}: already cloned, skipping")

      true ->
        case Git.clone_entry(entry) do
          :ok -> Igniter.add_notice(igniter, "#{name}: cloned")
          {:error, msg} -> Igniter.add_warning(igniter, "#{name}: clone failed — #{msg}")
        end
    end
  end
end
