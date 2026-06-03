defmodule Asher.FS do
  @moduledoc """
  Direct filesystem writes for the standalone `asher` escript (which has no
  igniter to compute/apply a diff). The `mix asher.*` tasks route the same
  `{path, content}` changes through `Igniter.create_new_file/4` instead.
  """

  @doc "Write `content` to `path`, creating parent directories as needed."
  @spec write!(Path.t(), iodata()) :: :ok
  def write!(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end

  @doc "Apply a list of `{path, content}` changes via `write!/2`."
  @spec write_all!([{Path.t(), iodata()}]) :: :ok
  def write_all!(changes) do
    Enum.each(changes, fn {path, content} -> write!(path, content) end)
  end
end
