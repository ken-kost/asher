defmodule Asher.Workspace do
  @moduledoc """
  Path helpers for the asher workspace.

  The cloned org repos live at the project root (so `cd ash` works), the
  generated manifest lives in `priv/repos.json`, and per-contribution receipts
  live under `data/`.
  """

  @doc "The asher project root (the directory `mix` is run from)."
  @spec root() :: String.t()
  def root, do: File.cwd!()

  @doc "Where a repo named `name` is (or would be) cloned."
  @spec clone_path(String.t()) :: String.t()
  def clone_path(name), do: Path.join(root(), name)

  @doc "The committed dashboard directory of in-flight contributions."
  @spec data_root() :: String.t()
  def data_root, do: Path.join(root(), "data")

  @doc "The generated repo manifest path."
  @spec manifest_path() :: String.t()
  def manifest_path, do: Path.join([root(), "priv", "repos.json"])
end
