defmodule Mix.Tasks.Asher.Status do
  use Igniter.Mix.Task

  @example "mix asher.status"

  @shortdoc "List in-flight contributions recorded under data/"
  @moduledoc """
  #{@shortdoc}

  Reads every `data/*/contribution.json` receipt and prints a dashboard of
  in-flight contributions: name, category, repos, branch and PR links. Read-only.

  ## Example

  ```sh
  #{@example}
  ```
  """

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{group: :asher, example: @example}
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    Asher.Status.print()
    igniter
  end
end
