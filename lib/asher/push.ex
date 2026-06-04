defmodule Asher.Push do
  @moduledoc """
  The `push` flow, shared by the escript and the mix task: pick a prepared
  contribution, review (and optionally edit) each PR body, choose draft or ready,
  then push the branch and open the PR. Returns the receipt file changes for the
  caller to write (via `Asher.FS` or igniter).
  """

  alias Asher.{Console, Contribute, Contribution, Contributions, Editor, Github}

  @doc """
  Run push for `slug` (or interactively pick one when nil). `opts` may carry
  `:draft` (true/false to skip the prompt). Returns `{:ok, file_changes}` or
  `{:error, message}`.
  """
  @spec run(String.t() | nil, keyword()) :: {:ok, [{Path.t(), String.t()}]} | {:error, String.t()}
  def run(slug, opts) do
    with :ok <- Github.ensure_available!(),
         :ok <- Github.ensure_authed!(),
         {:ok, owner} <- Github.current_user(),
         {:ok, contribution} <- select(slug) do
      meta = publish_all(contribution.meta, owner, opts)
      report(meta)
      {:ok, Contribution.files_for_meta(meta)}
    end
  end

  defp select(nil) do
    case Contributions.list() do
      [] ->
        {:error, "No contributions found. Run `asher init` (or `mix asher.init`) to start one."}

      [only] ->
        {:ok, only}

      many ->
        {:ok,
         Console.select(
           "Which contribution do you want to push?",
           many,
           display: &"#{&1.meta["name"]} (#{&1.meta["branch"]})"
         )}
    end
  end

  defp select(slug) do
    case Contributions.find(slug) do
      nil ->
        {:error, "No contribution matching #{inspect(slug)}. Run `asher status` to list them."}

      contribution ->
        {:ok, contribution}
    end
  end

  defp publish_all(meta, owner, opts) do
    survey = Contributions.to_survey(meta)
    branch = Contribution.branch_name(survey.category, survey.slug)

    Enum.reduce(survey.repos, meta, fn entry, meta ->
      full = entry["full_name"]
      existing = Enum.find(meta["repos"], &(&1["full_name"] == full)) || %{}

      if existing["status"] == "open" do
        Console.say("\n#{full}: PR already open — #{existing["pr_url"]} (skipping)")
        meta
      else
        info = publish_one(survey, entry, owner, branch, opts)
        Contributions.put_repo(meta, full, info)
      end
    end)
  end

  defp publish_one(survey, entry, owner, branch, opts) do
    title = Contribute.pr_title(survey)
    body = Contribute.pr_body(survey, entry)

    Console.say("\n#{entry["full_name"]} — PR title: #{title}\n")
    Console.say(body)

    body =
      if Console.yes?("Edit the PR body before opening it?", false),
        do: Editor.edit(body),
        else: body

    draft? = draft_choice(opts)

    Contribute.publish_one(entry, owner, branch: branch, title: title, body: body, draft: draft?)
  end

  defp draft_choice(opts) do
    case Keyword.get(opts, :draft) do
      nil -> Console.yes?("Open the PR as a draft?", true)
      bool -> bool
    end
  end

  defp report(meta) do
    Console.say("")

    Enum.each(meta["repos"], fn r ->
      case r do
        %{"pr_url" => url} when is_binary(url) -> Console.say("✓ #{r["full_name"]}: #{url}")
        %{"status" => "error", "error" => e} -> Console.warn("✗ #{r["full_name"]}: #{e}")
        _ -> :ok
      end
    end)
  end
end
