defmodule Asher.Editor do
  @moduledoc """
  Open text in the user's `$EDITOR` (or `$VISUAL`) for editing. Best-effort and
  terminal-only — used by `push` to let the contributor tweak the PR body before
  the PR is opened. Falls back to "edit this file, then press Enter" when no
  editor is configured or it can't be launched.
  """

  alias Asher.{Console, Shell}

  @doc "Edit `text` and return the result (or the original on EOF/failure)."
  @spec edit(String.t(), keyword()) :: String.t()
  def edit(text, opts \\ []) do
    suffix = Keyword.get(opts, :suffix, ".md")
    path = Path.join(System.tmp_dir!(), "asher-#{System.unique_integer([:positive])}#{suffix}")
    File.write!(path, text)

    open(System.get_env("VISUAL") || System.get_env("EDITOR"), path)

    edited = File.read!(path)
    File.rm(path)
    edited
  end

  # Launch the editor attached to the controlling terminal so full-screen editors
  # (vim, nano, …) work even though we're not the foreground process.
  defp open(nil, path), do: wait_for_manual_edit(path)

  defp open(editor, path) do
    case Shell.cmd("sh", ["-c", "#{editor} #{path} < /dev/tty > /dev/tty 2>&1"]) do
      {_out, 0} -> :ok
      _ -> wait_for_manual_edit(path)
    end
  end

  defp wait_for_manual_edit(path) do
    Console.warn("Could not open an editor. Edit this file, then press Enter:\n  #{path}")
    Console.prompt("")
  end
end
