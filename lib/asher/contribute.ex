defmodule Asher.Contribute do
  @moduledoc """
  The contribution side effects, shared by `mix asher.init` and the `asher init`
  escript: for each selected repo, clone → branch → fork → push → open the draft
  PR. Igniter-free (uses `Asher.Git`/`Asher.Github`/`Asher.Console`); callers
  handle writing the `data/` receipt and any final summary.
  """

  alias Asher.{Console, Contribution, Git, Github}

  @doc """
  Run the side effects for every selected repo. Returns a map of
  `full_name => %{status: "ok"|"error", pr_url|error, branch}`.
  """
  @spec run(map(), String.t()) :: %{optional(String.t()) => map()}
  def run(survey, owner) do
    branch = Contribution.branch_name(survey.category, survey.slug)

    survey.repos
    |> Enum.map(fn entry -> {entry["full_name"], one_repo(entry, survey, owner, branch)} end)
    |> Map.new()
  end

  @doc "Print the contribution summary."
  @spec print_summary(map(), String.t() | nil, boolean()) :: :ok
  def print_summary(survey, owner, dry_run) do
    Console.say("""

    #{if dry_run, do: "DRY RUN — ", else: ""}Contribution summary
      name:     #{survey.name}
      category: #{survey.category}
      branch:   #{Contribution.branch_name(survey.category, survey.slug)}
      repos:    #{Enum.map_join(survey.repos, ", ", & &1["full_name"])}
      issue:    #{issue_summary(survey.issue)}
      fork:     #{owner || "(resolved at run time)"}
    """)
  end

  @doc "Print the planned actions (used for dry runs)."
  @spec print_plan(map(), String.t() | nil) :: :ok
  def print_plan(survey, owner) do
    branch = Contribution.branch_name(survey.category, survey.slug)
    Console.say("Planned actions (no changes will be made):")

    Enum.each(survey.repos, fn entry ->
      Console.say(
        "  #{entry["full_name"]}: branch #{branch} → fork to #{owner || "<you>"} → push → open draft PR"
      )
    end)
  end

  @doc "Summarize results as `{ok_lines, failed_lines}` for the caller to report."
  @spec summarize(%{optional(String.t()) => map()}) :: {[String.t()], [String.t()]}
  def summarize(results) do
    {ok, failed} = Enum.split_with(results, fn {_full, r} -> r.status == "ok" end)

    {Enum.map(ok, fn {full, r} -> "#{full}: #{r.pr_url}" end),
     Enum.map(failed, fn {full, r} -> "#{full}: #{r.error}" end)}
  end

  # --- per-repo side effects -------------------------------------------------

  defp one_repo(entry, survey, owner, branch) do
    org = entry["org"]
    name = entry["name"]
    full = entry["full_name"]
    Console.say("\n== #{full} ==")

    with :ok <- step("clone", Git.ensure_cloned(name)),
         {:ok, _} <- step("fetch", Git.fetch(name, "origin")),
         base <- Github.default_branch(org, name),
         {:ok, _} <- step("branch #{branch}", Git.checkout_new_branch(name, branch, base)),
         :ok <- step("fork", Github.ensure_fork(org, name, owner)),
         :ok <- step("fork remote", Git.ensure_fork_remote(name, owner)),
         {:ok, _} <- step("commit", Git.empty_commit(name, commit_message(branch, survey))),
         :ok <- step("push", Git.push(name, "fork", branch)),
         {:ok, url} <-
           step(
             "draft PR",
             Github.ensure_draft_pr(
               org,
               name,
               owner,
               branch,
               base,
               pr_title(survey),
               pr_body(survey, entry)
             )
           ) do
      Console.say("  ✓ draft PR: #{url}")
      %{status: "ok", pr_url: url, branch: branch}
    else
      {:error, msg} ->
        Console.warn("  ✗ #{full}: #{msg}")
        %{status: "error", error: to_string(msg), branch: branch}
    end
  end

  defp step(label, result) do
    case result do
      :ok -> Console.say("  · #{label}")
      {:ok, _} -> Console.say("  · #{label}")
      {:error, _} -> :noop
    end

    result
  end

  # --- PR content ------------------------------------------------------------

  defp commit_message(branch, survey) do
    "chore: scaffold #{branch}\n\nInitial empty commit to open the draft PR for \"#{survey.name}\"."
  end

  @doc false
  # e.g. "fix: Add upsert support", "test: Cover the multitenancy path".
  def pr_title(survey), do: "#{Contribution.category_prefix(survey.category)}: #{survey.name}"

  # The standard ash-project pull request template.
  @checklist """
  # Contributor checklist

  Leave anything that you believe does not apply unchecked.

  - [ ] I accept the [AI Policy](https://github.com/ash-project/.github/blob/main/AI_POLICY.md), or AI was not used in the creation of this PR.
  - [ ] Bug fixes include regression tests
  - [ ] Chores
  - [ ] Documentation changes
  - [ ] Features include unit/acceptance tests
  - [ ] Refactoring
  - [ ] Update dependencies\
  """

  @doc false
  # The PR body: the linked issue first (when provided), then the ash-project
  # contributor checklist, then the details asher gathered. Checklist items are
  # left unchecked for the contributor to fill in (including the AI Policy
  # acceptance — asher won't accept it on your behalf).
  def pr_body(survey, entry) do
    folder = Contribution.folder_name(survey.slug, Enum.map(survey.repos, & &1["name"]))

    [issue_reference(survey.issue, entry), @checklist, details(survey, folder)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp details(survey, folder) do
    """
    ## Details

    - **Category:** #{survey.category}
    - **Repos:** #{Enum.map_join(survey.repos, ", ", & &1["full_name"])}
    - **Labels:** #{labels(survey.scraped)}

    _Scaffolded by [asher](https://github.com/ash-project). Tracking folder: `data/#{folder}`._\
    """
  end

  # `Closes #n` on the repo that owns the issue; a link on the others; "" if none.
  defp issue_reference(nil, _entry), do: ""

  defp issue_reference(issue, entry) do
    cond do
      is_nil(issue.number) -> ""
      issue.full_name == entry["full_name"] -> "Closes ##{issue.number}"
      issue.url -> "Related issue: #{issue.url}"
      true -> "Related issue: #{issue.full_name}##{issue.number}"
    end
  end

  defp labels(%{"labels" => labels}) when labels != [], do: Enum.join(labels, ", ")
  defp labels(_), do: "—"

  defp issue_summary(nil), do: "(none)"
  defp issue_summary(issue), do: issue.url || "#{issue.full_name}##{issue.number}"
end
