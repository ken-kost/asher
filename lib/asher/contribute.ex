defmodule Asher.Contribute do
  @moduledoc """
  Contribution side effects, shared by the init and push commands (escript and
  mix task).

  `prepare/2` (init) clones each repo, branches off its default branch, and forks
  it — but opens **no** PR. `publish_one/3` (push) ensures a commit, pushes the
  branch to the fork, and opens the PR (draft or ready). Igniter-free; callers
  write the `data/` receipt.
  """

  alias Asher.{Console, Contribution, Git, Github}

  # --- init: prepare locally (no push, no PR) --------------------------------

  @doc """
  Prepare each selected repo: clone, branch off the default branch, and fork.
  Opens no PR. Returns `full_name => %{"status" => "prepared" | "error", ...}`.
  """
  @spec prepare(map(), String.t()) :: %{optional(String.t()) => map()}
  def prepare(survey, owner) do
    branch = Contribution.branch_name(survey.category, survey.slug)

    survey.repos
    |> Enum.map(fn entry -> {entry["full_name"], prepare_one(entry, owner, branch)} end)
    |> Map.new()
  end

  defp prepare_one(entry, owner, branch) do
    org = entry["org"]
    name = entry["name"]
    full = entry["full_name"]
    Console.say("\n== #{full} ==")

    with {:ok, _base} <- ready_branch(org, name, owner, branch) do
      %{"status" => "prepared", "branch" => branch}
    else
      {:error, msg} ->
        Console.warn("  ✗ #{full}: #{msg}")
        %{"status" => "error", "branch" => branch, "error" => to_string(msg)}
    end
  end

  # --- push: publish one prepared repo ---------------------------------------

  @doc """
  Publish one repo: ensure the branch/fork, ensure a commit, push to the fork,
  and open the PR (draft when `opts[:draft]`). `opts` carries `:branch`, `:title`,
  `:body`, `:draft`. Returns an updated status map.
  """
  @spec publish_one(map(), String.t(), keyword()) :: map()
  def publish_one(entry, owner, opts) do
    org = entry["org"]
    name = entry["name"]
    full = entry["full_name"]
    branch = Keyword.fetch!(opts, :branch)
    draft? = Keyword.fetch!(opts, :draft)
    label = if draft?, do: "draft PR", else: "PR"
    Console.say("\n== #{full} ==")

    with {:ok, base} <- ready_branch(org, name, owner, branch),
         {:ok, _} <- step("commit", Git.ensure_commit(name, base, branch, commit_message(branch))),
         :ok <- step("push", Git.push(name, "fork", branch)),
         {:ok, url} <-
           step(
             label,
             Github.ensure_pr(org, name, owner, branch, base, opts[:title], opts[:body], draft?)
           ) do
      Console.say("  ✓ #{label}: #{url}")
      %{"status" => "open", "branch" => branch, "pr_url" => url, "draft" => draft?}
    else
      {:error, msg} ->
        Console.warn("  ✗ #{full}: #{msg}")
        %{"status" => "error", "branch" => branch, "error" => to_string(msg)}
    end
  end

  # Lazily clone the repo (or update it from remote if already present), fetch,
  # branch off the latest default branch, fork, add the fork remote. Idempotent
  # and shared by prepare and publish. Returns `{:ok, base}`.
  defp ready_branch(org, name, owner, branch) do
    with {:ok, _} <- ensure_repo(name),
         {:ok, _} <- step("fetch latest", Git.fetch(name, "origin")),
         base <- Github.default_branch(org, name),
         {:ok, _} <-
           step(
             "branch #{branch} (off origin/#{base})",
             Git.checkout_new_branch(name, branch, base)
           ),
         :ok <- step("fork", Github.ensure_fork(org, name, owner)),
         :ok <- step("fork remote", Git.ensure_fork_remote(name, owner)) do
      {:ok, base}
    end
  end

  # Clone on first use; if already present, leave it and let the fetch above
  # sync it with the remote.
  defp ensure_repo(name) do
    if Git.cloned?(name) do
      Console.say("  · #{name} already present — updating from remote")
      {:ok, :present}
    else
      Console.say("  · cloning #{name}")

      case Git.ensure_cloned(name) do
        :ok -> {:ok, :cloned}
        error -> error
      end
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

  # --- output ----------------------------------------------------------------

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

  @doc "Print what init will prepare (no PRs are opened here)."
  @spec print_plan(map(), String.t() | nil) :: :ok
  def print_plan(survey, owner) do
    branch = Contribution.branch_name(survey.category, survey.slug)
    Console.say("Planned (init prepares locally — no PR; run `asher push` to open it):")

    Enum.each(survey.repos, fn entry ->
      Console.say(
        "  #{entry["full_name"]}: clone → branch #{branch} → fork to #{owner || "<you>"}"
      )
    end)
  end

  @doc "Summarize results as `{ok_lines, error_lines}` for the caller to report."
  @spec summarize(%{optional(String.t()) => map()}) :: {[String.t()], [String.t()]}
  def summarize(results) do
    Enum.reduce(results, {[], []}, fn {full, r}, {ok, err} ->
      case r["status"] do
        "open" -> {ok ++ ["#{full}: #{r["pr_url"]}"], err}
        "prepared" -> {ok ++ ["#{full}: branch `#{r["branch"]}` ready"], err}
        "error" -> {ok, err ++ ["#{full}: #{r["error"]}"]}
        _ -> {ok, err}
      end
    end)
  end

  # --- PR content ------------------------------------------------------------

  defp commit_message(branch) do
    "chore: start #{branch}\n\nInitial empty commit so the PR has a diff to open against."
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
