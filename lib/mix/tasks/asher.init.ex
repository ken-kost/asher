defmodule Mix.Tasks.Asher.Init do
  use Igniter.Mix.Task

  alias Asher.{Console, Contribute, Contribution, Github, Repos, Survey}

  @example "mix asher.init"

  @shortdoc "Interactively scaffold a contribution (survey → branch → fork → draft PR)"
  @moduledoc """
  #{@shortdoc}

  Runs an interactive survey — does it have an issue (scraped if so), what
  category, which repo(s), and a name — then, for each selected repo: clones it
  if needed, branches off the default branch, forks it to your account, pushes
  the branch, and opens a **draft PR** referencing the issue. A receipt with all
  the gathered data is written under `data/`.

  Requires the `gh` CLI, installed and authenticated (`gh auth login`). Run it
  in a terminal — the survey is interactive.

  > Tip: the same flow is available as the standalone `asher init` escript (see
  > the README), which does not require a Mix project.

  ## Example

  ```sh
  #{@example}
  mix asher.init --dry-run   # walk the survey, print the plan, preview the
                             # receipt — but write nothing and touch no remotes
  ```

  ## Options

  * `--dry-run` / `-d` - preview only: run the survey, print the planned actions,
    and show the `data/` receipt diff, but create no branches, forks, commits or
    PRs and write no files. (This is igniter's built-in dry-run, so nothing is
    written to disk.)
  """

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :asher,
      example: @example,
      positional: [],
      schema: [dry_run: :boolean],
      aliases: [d: :dry_run]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    dry_run = !!igniter.args.options[:dry_run]

    case Repos.all() do
      [] ->
        Igniter.add_issue(
          igniter,
          "No repos are tracked yet. Run `mix asher.setup <org>` first (e.g. `mix asher.setup ash-project`)."
        )

      repos ->
        preflight(igniter, repos, dry_run)
    end
  end

  defp preflight(igniter, repos, true), do: contribute(igniter, repos, true, nil)

  defp preflight(igniter, repos, false) do
    with :ok <- Github.ensure_available!(),
         :ok <- Github.ensure_authed!(),
         {:ok, owner} <- Github.current_user() do
      contribute(igniter, repos, false, owner)
    else
      {:error, msg} -> Igniter.add_issue(igniter, msg)
    end
  end

  defp contribute(igniter, repos, dry_run, owner) do
    survey = Survey.run(repos)
    Contribute.print_summary(survey, owner, dry_run)

    cond do
      dry_run ->
        Contribute.print_plan(survey, owner)
        folder = Contribution.folder_name(survey.slug, Enum.map(survey.repos, & &1["name"]))

        igniter
        |> Igniter.assign(:quiet_on_no_changes?, true)
        |> Igniter.add_notice(
          "Dry run — no branches, forks, PRs or files were created. A receipt would be written to data/#{folder}/."
        )

      not Console.yes?("Proceed: clone/branch/fork/push and open draft PR(s)?") ->
        Igniter.add_notice(igniter, "Aborted before any side effects. Nothing changed.")

      true ->
        results = Contribute.run(survey, owner)

        igniter
        |> write_receipt(survey, owner, results)
        |> summarize(results)
    end
  end

  defp write_receipt(igniter, survey, owner, results) do
    survey
    |> Contribution.receipt_files(owner, results, false)
    |> Enum.reduce(igniter, fn {path, content}, igniter ->
      Igniter.create_new_file(igniter, path, content, on_exists: :overwrite)
    end)
  end

  defp summarize(igniter, results) do
    {ok, failed} = Contribute.summarize(results)

    igniter = Enum.reduce(ok, igniter, fn line, igniter -> Igniter.add_notice(igniter, line) end)
    Enum.reduce(failed, igniter, fn line, igniter -> Igniter.add_warning(igniter, line) end)
  end
end
