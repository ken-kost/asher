defmodule Asher.Test.StubShell do
  @moduledoc """
  Test `Asher.Shell` implementation. Delegates every `cmd/3` call to a function
  stored in `:asher, :shell_fun`, letting each test script the exact `git`/`gh`/
  `curl` responses it expects. Falls back to a successful empty response.

  Use `Asher.Test.StubShell.stub(fn bin, args, opts -> {output, status} end)`
  in a test (with `async: false`, since it sets application env).
  """

  @behaviour Asher.Shell

  @impl Asher.Shell
  def cmd(bin, args, opts) do
    fun = Application.get_env(:asher, :shell_fun, fn _bin, _args, _opts -> {"", 0} end)
    fun.(bin, args, opts)
  end

  @doc "Install this stub and the given response function for the current test."
  @spec stub((binary(), [binary()], keyword() -> {binary(), non_neg_integer()})) :: :ok
  def stub(fun) do
    Application.put_env(:asher, :shell, __MODULE__)
    Application.put_env(:asher, :shell_fun, fun)
  end

  @doc "Reset shell config back to the default (call from `on_exit`)."
  @spec reset() :: :ok
  def reset do
    Application.delete_env(:asher, :shell)
    Application.delete_env(:asher, :shell_fun)
  end
end
