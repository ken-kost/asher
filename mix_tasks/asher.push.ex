defmodule Mix.Tasks.Asher.Push do
  use Igniter.Mix.Task

  @example "mix asher.push"

  @shortdoc "Review and open the PR(s) for a prepared contribution"
  @moduledoc """
  #{@shortdoc}

  Picks a contribution prepared by `mix asher.init` (pass its `slug`, or choose
  interactively), shows each PR title and body — letting you edit the body in
  your `$EDITOR` — asks whether to open it as a draft, then pushes the branch to
  your fork and opens the PR. The `data/` receipt is updated with the PR link(s).

  Requires the `gh` CLI, installed and authenticated (`gh auth login`).

  ## Example

  ```sh
  #{@example}
  mix asher.push add-upsert-support      # a specific contribution
  mix asher.push --no-draft              # open a ready-for-review PR
  ```

  ## Options

  * `--draft` / `--no-draft` - open as a draft (or not) without being asked.
  """

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :asher,
      example: @example,
      positional: [{:slug, optional: true}],
      schema: [draft: :boolean]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    slug = igniter.args.positional[:slug]
    opts = [draft: igniter.args.options[:draft]]

    case Asher.Push.run(slug, opts) do
      {:ok, changes} -> Asher.IgniterWrites.write(igniter, changes)
      {:error, msg} -> Igniter.add_issue(igniter, msg)
    end
  end
end
