defmodule Asher.CLI do
  @moduledoc """
  Entry point for the standalone `asher` escript.

  Provides the same workflow as the `mix asher.*` tasks — `setup`, `init`,
  `sync`, `status` — but as a global command that bundles its dependencies and
  needs no Mix project. It reuses asher's igniter-free core (`Asher.Survey`,
  `Asher.Contribute`, `Asher.Manifest`, `Asher.Github`, `Asher.Git`) and writes
  files directly via `Asher.FS`.

  Build with `mix escript.build`; install with `mix escript.install github <you>/asher`.
  """

  alias Asher.{
    Console,
    Contribute,
    Contribution,
    FS,
    Git,
    Github,
    Manifest,
    Repos,
    Status,
    Survey,
    Tasks
  }

  @version Mix.Project.config()[:version] || "0.0.0"

  @doc false
  @spec main([String.t()]) :: any()
  def main(argv) do
    case argv do
      ["setup" | rest] ->
        setup(rest)

      ["init" | rest] ->
        init(rest)

      ["sync" | rest] ->
        sync(rest)

      ["status" | _] ->
        Status.print()

      [flag] when flag in ~w(-v --version) ->
        Console.say("asher #{@version}")

      [flag] when flag in ~w(-h --help help) ->
        Console.say(usage())

      [] ->
        Console.say(usage())

      [unknown | _] ->
        Console.warn("Unknown command: #{unknown}\n") && Console.say(usage()) && halt(2)
    end
  end

  # --- sync ------------------------------------------------------------------

  defp sync(rest) do
    {opts, positional, _} =
      OptionParser.parse(rest, strict: [lang: :string, include: :string, exclude: :string])

    org = Github.parse_org(List.first(positional))
    do_sync(org, Tasks.parse_filter_opts(opts))
  end

  # Returns the synced entries (or halts on error).
  defp do_sync(org, filter_opts) do
    case Github.fetch_org_repos(org) do
      {:ok, raw} ->
        entries = Repos.filter(raw, org, filter_opts)
        {merged, changes} = Manifest.changes(org, entries)
        FS.write_all!(changes)

        Console.say(
          "Synced #{length(entries)} repos from #{org}. Manifest tracks #{length(merged)} repos."
        )

        entries

      {:error, msg} ->
        Console.warn("Sync failed: #{msg}")
        halt(1)
    end
  end

  # --- setup -----------------------------------------------------------------

  defp setup(rest) do
    {opts, positional, _} =
      OptionParser.parse(rest,
        strict: [lang: :string, include: :string, exclude: :string, no_clone: :boolean]
      )

    {org_arg, repo_names} =
      case positional do
        [] -> {nil, []}
        [org | repos] -> {org, repos}
      end

    org = Github.parse_org(org_arg)
    entries = do_sync(org, Tasks.parse_filter_opts(opts))

    cond do
      opts[:no_clone] -> Console.say("Skipped cloning (--no-clone).")
      true -> clone(entries, repo_names)
    end
  end

  defp clone(entries, names) do
    entries
    |> filter_by_names(names)
    |> Enum.each(fn entry ->
      name = entry["name"]

      cond do
        Git.cloned?(name) ->
          Console.say("#{name}: already cloned, skipping")

        true ->
          case Git.clone_entry(entry) do
            :ok -> Console.say("#{name}: cloned")
            {:error, msg} -> Console.warn("#{name}: clone failed — #{msg}")
          end
      end
    end)
  end

  defp filter_by_names(entries, []), do: entries
  defp filter_by_names(entries, names), do: Enum.filter(entries, &(&1["name"] in names))

  # --- init ------------------------------------------------------------------

  defp init(rest) do
    {opts, _positional, _} = OptionParser.parse(rest, strict: [dry_run: :boolean])
    dry_run = !!opts[:dry_run]

    case Repos.all() do
      [] ->
        Console.warn(
          "No repos tracked yet. Run `asher setup <org>` first (e.g. asher setup ash-project)."
        )

        halt(1)

      repos when dry_run ->
        run_init(repos, true, nil)

      repos ->
        with :ok <- Github.ensure_available!(),
             :ok <- Github.ensure_authed!(),
             {:ok, owner} <- Github.current_user() do
          run_init(repos, false, owner)
        else
          {:error, msg} ->
            Console.warn(msg)
            halt(1)
        end
    end
  end

  defp run_init(repos, dry_run, owner) do
    survey = Survey.run(repos)
    Contribute.print_summary(survey, owner, dry_run)

    cond do
      dry_run ->
        Contribute.print_plan(survey, owner)
        folder = Contribution.folder_name(survey.slug, Enum.map(survey.repos, & &1["name"]))
        Console.say("\nDry run — nothing created. A receipt would be written to data/#{folder}/.")

      not Console.yes?("Proceed: clone/branch/fork/push and open draft PR(s)?") ->
        Console.say("Aborted. Nothing changed.")

      true ->
        results = Contribute.run(survey, owner)
        survey |> Contribution.receipt_files(owner, results, false) |> FS.write_all!()
        report(results)
    end
  end

  defp report(results) do
    {ok, failed} = Contribute.summarize(results)
    Console.say("")
    Enum.each(ok, fn line -> Console.say("✓ #{line}") end)
    Enum.each(failed, fn line -> Console.warn("✗ #{line}") end)
  end

  # --- help ------------------------------------------------------------------

  defp usage do
    """
    asher #{@version} — scaffold contributions to a GitHub org's repos.

    USAGE
      asher setup <org> [repo ...] [--lang L] [--include a,b] [--exclude c,d] [--no-clone]
          Sync an org's active repos into priv/repos.json and clone them here.
      asher init [--dry-run]
          Interactive survey → branch → fork → push → draft PR. Needs `gh` + `gh auth login`.
      asher sync <org> [--lang L] [--include a,b] [--exclude c,d]
          Sync the manifest only (no cloning).
      asher status
          List in-flight contributions recorded under data/.
      asher --help | --version

    EXAMPLES
      asher setup ash-project
      asher setup ash-project --lang elixir
      asher init
      asher init --dry-run
    """
  end

  defp halt(code), do: System.halt(code)
end
