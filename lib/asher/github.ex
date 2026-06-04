defmodule Asher.Github do
  @moduledoc """
  GitHub access for asher.

  * Org/issue reference parsing (pure).
  * Reading the public org repo list over HTTP via `curl` (works unauthenticated).
  * Everything that needs auth — scraping an issue, forking, opening the draft
    PR, resolving the current user/default branch — via the `gh` CLI.

  All process calls go through `Asher.Shell` so they can be stubbed in tests.
  """

  alias Asher.Shell

  @api "https://api.github.com"

  # ---------------------------------------------------------------------------
  # Parsing (pure)
  # ---------------------------------------------------------------------------

  @doc """
  Normalize an org reference to its slug. Accepts a bare slug, a full URL, or a
  `github.com/...` path. Defaults to `ash-project` when blank/nil.
  """
  @spec parse_org(String.t() | nil) :: String.t()
  def parse_org(arg) do
    arg
    |> to_string()
    |> String.trim()
    |> case do
      "" ->
        "ash-project"

      ref ->
        ref
        |> String.replace(~r{^https?://}, "")
        |> String.replace(~r{^github\.com/}, "")
        |> String.replace(~r{^orgs/}, "")
        |> String.trim("/")
        |> String.split("/")
        |> List.first()
    end
  end

  @doc """
  Parse an issue reference into `{:ok, %{org:, repo:, number:}}`.

  Accepts a full issue/PR URL (`https://github.com/<org>/<repo>/issues/<n>`) or
  the shorthand `<org>/<repo>#<n>`.
  """
  @spec parse_issue_ref(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_issue_ref(ref) do
    ref = ref |> to_string() |> String.trim()

    cond do
      String.contains?(ref, "github.com/") ->
        case Regex.run(~r{github\.com/([^/\s]+)/([^/\s]+)/(?:issues|pull)/(\d+)}, ref) do
          [_, org, repo, n] -> {:ok, %{org: org, repo: repo, number: String.to_integer(n)}}
          _ -> {:error, "could not parse issue URL: #{ref}"}
        end

      Regex.match?(~r{^[^/\s]+/[^#\s]+#\d+$}, ref) ->
        [_, org, repo, n] = Regex.run(~r{^([^/]+)/([^#]+)#(\d+)$}, ref)
        {:ok, %{org: org, repo: repo, number: String.to_integer(n)}}

      true ->
        {:error, "unrecognized issue reference #{inspect(ref)} — use a full URL or org/repo#123"}
    end
  end

  # ---------------------------------------------------------------------------
  # gh availability / auth / identity
  # ---------------------------------------------------------------------------

  @doc "Is the `gh` CLI installed?"
  @spec available?() :: boolean()
  def available?, do: Shell.available?("gh")

  @doc "`:ok` if `gh` is installed, otherwise an actionable error."
  @spec ensure_available!() :: :ok | {:error, String.t()}
  def ensure_available! do
    if available?() do
      :ok
    else
      {:error,
       "The GitHub CLI `gh` is not installed. Install it from https://cli.github.com/ and run `gh auth login`."}
    end
  end

  @doc "`:ok` if `gh` is authenticated, otherwise an actionable error."
  @spec ensure_authed!() :: :ok | {:error, String.t()}
  def ensure_authed! do
    case Shell.cmd("gh", ["auth", "status"], stderr_to_stdout: true) do
      {_out, 0} ->
        :ok

      {out, _} ->
        {:error, "`gh` is not authenticated. Run `gh auth login`.\n" <> String.trim(out)}
    end
  end

  @doc "The login of the authenticated `gh` user (the fork owner)."
  @spec current_user() :: {:ok, String.t()} | {:error, String.t()}
  def current_user do
    case Shell.cmd("gh", ["api", "user", "--jq", ".login"], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, "could not resolve gh user: #{String.trim(out)}"}
    end
  end

  @doc "The default branch of a repo (falls back to `main`)."
  @spec default_branch(String.t(), String.t()) :: String.t()
  def default_branch(org, repo) do
    case Shell.cmd(
           "gh",
           [
             "repo",
             "view",
             "#{org}/#{repo}",
             "--json",
             "defaultBranchRef",
             "--jq",
             ".defaultBranchRef.name"
           ],
           stderr_to_stdout: true
         ) do
      {out, 0} ->
        case String.trim(out) do
          "" -> "main"
          name -> name
        end

      _ ->
        "main"
    end
  end

  # ---------------------------------------------------------------------------
  # Reading the org repo list (public, via curl)
  # ---------------------------------------------------------------------------

  @doc "Fetch all public repos for `org` from the GitHub REST API (paginated)."
  @spec fetch_org_repos(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def fetch_org_repos(org), do: fetch_pages(org, 1, [])

  defp fetch_pages(org, page, acc) do
    url = "#{@api}/orgs/#{org}/repos?per_page=100&type=public&page=#{page}"

    case Shell.cmd("curl", ["-sSL", "-H", "Accept: application/vnd.github+json", url],
           stderr_to_stdout: true
         ) do
      {out, 0} ->
        case Jason.decode(out) do
          {:ok, list} when is_list(list) ->
            acc = acc ++ list
            if length(list) < 100, do: {:ok, acc}, else: fetch_pages(org, page + 1, acc)

          {:ok, %{"message" => msg}} ->
            {:error, "GitHub API error for org #{inspect(org)}: #{msg}"}

          _ ->
            {:error, "unexpected GitHub API response for org #{inspect(org)}"}
        end

      {out, _} ->
        {:error, "curl failed: #{String.trim(out)}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Issue scraping (auth, via gh)
  # ---------------------------------------------------------------------------

  @doc "Scrape an issue's title/body/labels/state via `gh issue view`."
  @spec view_issue(String.t(), String.t(), integer()) :: {:ok, map()} | {:error, String.t()}
  def view_issue(org, repo, number) do
    args = [
      "issue",
      "view",
      to_string(number),
      "--repo",
      "#{org}/#{repo}",
      "--json",
      "title,body,labels,state,number,url,author"
    ]

    case Shell.cmd("gh", args, stderr_to_stdout: true) do
      {out, 0} ->
        case Jason.decode(out) do
          {:ok, data} -> {:ok, normalize_issue(data)}
          _ -> {:error, "could not parse issue JSON"}
        end

      {out, _} ->
        {:error, String.trim(out)}
    end
  end

  defp normalize_issue(data) do
    %{
      "title" => data["title"],
      "body" => data["body"],
      "state" => data["state"],
      "number" => data["number"],
      "url" => data["url"],
      "labels" => Enum.map(data["labels"] || [], & &1["name"]),
      "author" => get_in(data, ["author", "login"])
    }
  end

  # ---------------------------------------------------------------------------
  # Fork + draft PR (auth, via gh) — all idempotent
  # ---------------------------------------------------------------------------

  @doc "Ensure a fork of `org/repo` exists under the authenticated account."
  @spec ensure_fork(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def ensure_fork(org, repo, _owner) do
    case Shell.cmd("gh", ["repo", "fork", "#{org}/#{repo}", "--clone=false"],
           stderr_to_stdout: true
         ) do
      {_out, 0} -> :ok
      {out, _} -> if already?(out), do: :ok, else: {:error, String.trim(out)}
    end
  end

  @doc """
  Open a PR `owner:branch -> org:base`, as a draft when `draft?` is true,
  returning its URL. If one already exists, look it up and return that URL
  instead (idempotent).
  """
  @spec ensure_pr(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          boolean()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  def ensure_pr(org, repo, owner, branch, base, title, body, draft?) do
    draft_flag = if draft?, do: ["--draft"], else: []

    args =
      ["pr", "create", "--repo", "#{org}/#{repo}", "--head", "#{owner}:#{branch}", "--base", base] ++
        draft_flag ++ ["--title", title, "--body", body]

    case Shell.cmd("gh", args, stderr_to_stdout: true) do
      {out, 0} ->
        {:ok, extract_url(out)}

      {out, _} ->
        if already?(out),
          do: existing_pr_url(org, repo, owner, branch),
          else: {:error, String.trim(out)}
    end
  end

  defp existing_pr_url(org, repo, owner, branch) do
    args = [
      "pr",
      "list",
      "--repo",
      "#{org}/#{repo}",
      "--head",
      "#{owner}:#{branch}",
      "--state",
      "all",
      "--json",
      "url",
      "--jq",
      ".[0].url"
    ]

    case Shell.cmd("gh", args, stderr_to_stdout: true) do
      {out, 0} ->
        case String.trim(out) do
          "" -> {:error, "a PR already exists but its URL could not be resolved"}
          url -> {:ok, url}
        end

      {out, _} ->
        {:error, String.trim(out)}
    end
  end

  defp already?(out), do: String.contains?(out, "already exists")

  defp extract_url(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.find(&String.contains?(&1, "github.com"))
    |> case do
      nil -> String.trim(out)
      url -> String.trim(url)
    end
  end
end
