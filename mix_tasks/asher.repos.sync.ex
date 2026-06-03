defmodule Mix.Tasks.Asher.Repos.Sync do
  use Igniter.Mix.Task

  alias Asher.{Github, Manifest, Repos}

  @example "mix asher.repos.sync ash-project --lang elixir"

  @shortdoc "Sync a GitHub org's active repos into priv/repos.json"
  @moduledoc """
  #{@shortdoc}

  Fetches the public repos of a GitHub organization, filters them down to the
  active contribution targets (excluding archived repos, forks and `.github`),
  and writes them into the committed manifest `priv/repos.json`. Re-running for
  the same org replaces that org's entries; running for a new org appends to the
  manifest. The managed block of cloned-repo paths in `.gitignore` is kept in
  sync automatically.

  ## Example

  ```sh
  #{@example}
  ```

  ## Arguments

  * `org` - org slug or URL (e.g. `ash-project` or `https://github.com/ash-project`).
    Defaults to `ash-project`.

  ## Options

  * `--lang` / `-l` - keep only repos whose primary language matches (e.g. `--lang elixir`)
  * `--include` - comma-separated repo names to keep regardless of filters
  * `--exclude` - comma-separated repo names to drop regardless of filters
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
    opts = Asher.Tasks.parse_filter_opts(igniter.args.options)

    case Github.fetch_org_repos(org) do
      {:ok, raw} ->
        entries = Repos.filter(raw, org, opts)
        {merged, changes} = Manifest.changes(org, entries)
        igniter = Asher.IgniterWrites.write(igniter, changes)
        orgs = merged |> Enum.map(& &1["org"]) |> Enum.uniq() |> length()

        Igniter.add_notice(
          igniter,
          "Synced #{length(entries)} repos from #{org}. Manifest now tracks #{length(merged)} repos across #{orgs} org(s)."
        )

      {:error, msg} ->
        Igniter.add_issue(igniter, "asher.repos.sync failed: #{msg}")
    end
  end
end
