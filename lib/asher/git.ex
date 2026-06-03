defmodule Asher.Git do
  @moduledoc """
  Idempotent git operations over the cloned repos, run through `Asher.Shell`.

  Shared by `mix asher.setup` (clone) and `mix asher.init` (branch, commit,
  push). Every helper is safe to re-run.
  """

  alias Asher.{Repos, Shell, Workspace}

  @doc "Whether `name` is already cloned in the workspace."
  @spec cloned?(String.t()) :: boolean()
  def cloned?(name), do: File.dir?(Path.join(Workspace.clone_path(name), ".git"))

  @doc "Clone a manifest entry into the workspace."
  @spec clone_entry(map()) :: :ok | {:error, String.t()}
  def clone_entry(entry) do
    dest = Workspace.clone_path(entry["name"])

    case Shell.cmd("git", ["clone", entry["clone_url"], dest], stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, _} -> {:error, "git clone failed: #{String.trim(out)}"}
    end
  end

  @doc "Clone `name` (looked up in the manifest) unless it is already present."
  @spec ensure_cloned(String.t()) :: :ok | {:error, String.t()}
  def ensure_cloned(name) do
    if cloned?(name), do: :ok, else: clone_entry(Repos.fetch!(name))
  end

  @doc "Fetch a remote (default `origin`)."
  @spec fetch(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch(name, remote \\ "origin"), do: git(name, ["fetch", remote])

  @doc "The currently checked-out branch."
  @spec current_branch(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def current_branch(name), do: git(name, ["rev-parse", "--abbrev-ref", "HEAD"])

  @doc "Whether a local branch exists."
  @spec branch_exists?(String.t(), String.t()) :: boolean()
  def branch_exists?(name, branch) do
    match?({:ok, _}, git(name, ["show-ref", "--verify", "--quiet", "refs/heads/#{branch}"]))
  end

  @doc """
  Check out `branch`, creating it from `origin/<base>` when it does not yet
  exist (idempotent — re-running just checks it out).
  """
  @spec checkout_new_branch(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def checkout_new_branch(name, branch, base) do
    if branch_exists?(name, branch) do
      git(name, ["checkout", branch])
    else
      git(name, ["checkout", "-b", branch, "origin/#{base}"])
    end
  end

  @doc "Create an empty commit so a draft PR has a diff to open against."
  @spec empty_commit(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def empty_commit(name, message), do: git(name, ["commit", "--allow-empty", "-m", message])

  @doc "Add the user's fork as a `fork` remote unless it is already present."
  @spec ensure_fork_remote(String.t(), String.t()) :: :ok | {:error, String.t()}
  def ensure_fork_remote(name, owner) do
    if match?({:ok, _}, git(name, ["remote", "get-url", "fork"])) do
      :ok
    else
      url = "https://github.com/#{owner}/#{name}.git"

      case git(name, ["remote", "add", "fork", url]) do
        {:ok, _} -> :ok
        {:error, m} -> {:error, m}
      end
    end
  end

  @doc "Push `branch` to `remote`, treating an up-to-date push as success."
  @spec push(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def push(name, remote, branch) do
    case git(name, ["push", "-u", remote, branch]) do
      {:ok, _} ->
        :ok

      {:error, out} ->
        if String.contains?(out, "up-to-date") or String.contains?(out, "up to date") do
          :ok
        else
          {:error, out}
        end
    end
  end

  defp git(name, args) do
    dest = Workspace.clone_path(name)

    case Shell.cmd("git", ["-C", dest | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, String.trim(out)}
    end
  end
end
