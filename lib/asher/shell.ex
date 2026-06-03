defmodule Asher.Shell do
  @moduledoc """
  A thin, injectable wrapper around `System.cmd/3`.

  Every `git`, `gh`, and `curl` invocation in asher goes through this module so
  that tests can swap in a stub implementation (via `config :asher, :shell`) and
  exercise the tasks without touching the network or the filesystem.
  """

  @callback cmd(binary(), [binary()], keyword()) ::
              {output :: binary(), exit_status :: non_neg_integer()}

  @doc "Run a command through the configured shell implementation."
  @spec cmd(binary(), [binary()], keyword()) :: {binary(), non_neg_integer()}
  def cmd(bin, args, opts \\ []), do: impl().cmd(bin, args, opts)

  @doc "Whether `bin` is available on the PATH."
  @spec available?(binary()) :: boolean()
  def available?(bin), do: System.find_executable(bin) != nil

  defp impl, do: Application.get_env(:asher, :shell, Asher.Shell.System)

  defmodule System do
    @moduledoc "Default `Asher.Shell` implementation backed by `System.cmd/3`."
    @behaviour Asher.Shell

    @impl Asher.Shell
    def cmd(bin, args, opts), do: Elixir.System.cmd(bin, args, opts)
  end
end
