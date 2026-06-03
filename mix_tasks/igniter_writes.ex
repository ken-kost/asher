defmodule Asher.IgniterWrites do
  @moduledoc false
  # Applies a list of `{path, content}` changes (from `Asher.Manifest`/
  # `Asher.Contribution`) onto an igniter. Lives with the mix tasks because it
  # depends on igniter, which is a dev/test-only dependency.

  @spec write(Igniter.t(), [{Path.t(), iodata()}]) :: Igniter.t()
  def write(igniter, changes) do
    Enum.reduce(changes, igniter, fn {path, content}, igniter ->
      Igniter.create_new_file(igniter, path, content, on_exists: :overwrite)
    end)
  end
end
