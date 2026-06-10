defmodule Mix.Tasks.Asher.Setup do
  use Igniter.Mix.Task

  alias Asher.{Github, Manifest, Repos, Tasks}

  @example "mix asher.setup ash-project"

  @shortdoc "Sync a GitHub org's active repos into the manifest"
  @moduledoc """
  #{@shortdoc}

  The "set me up" command: point it at an org and it syncs that org's active
  repos into `priv/repos.json` (and keeps the managed clone-ignore block in
  `.gitignore` in step). It does **not** clone anything — repos are cloned (and
  forked) lazily by `mix asher.init`/`asher init` when you actually select one,
  and an already-cloned repo is updated from its remote at that point.

  (This is equivalent to `mix asher.repos.sync`; `setup` is just the friendly
  first-run name.)

  ## Example

  ```sh
  #{@example}
  mix asher.setup ash-project --lang elixir   # only track Elixir repos
  ```

  ## Arguments

  * `org` - org slug or URL. Defaults to `ash-project`.

  ## Options

  * `--lang` / `-l` - keep only repos whose primary language matches
  * `--include` / `--exclude` - comma-separated overrides to the active-repo filter
  """

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :asher,
      example: @example,
      positional: [{:org, optional: true}],
      schema: [lang: :string, include: :string, exclude: :string],
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

        igniter
        |> Asher.IgniterWrites.write(changes)
        |> Igniter.add_notice(
          "Synced #{length(entries)} repos from #{org}. Run `mix asher.init` to start a contribution — repos are cloned on demand."
        )

      {:error, msg} ->
        Igniter.add_issue(igniter, "asher.setup failed: #{msg}")
    end
  end
end
