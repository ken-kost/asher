defmodule Asher do
  @moduledoc """
  Asher lowers the barrier to contributing to a whole GitHub organization's repos
  (the [Ash ecosystem](https://github.com/ash-project) is the flagship example).

  Point it at an org with `mix asher.setup <org>` to link and clone every active
  repo, then run `mix asher.init` to go from "I want to fix this issue" to a
  branched, forked, pushed **draft PR** in one interactive survey.

  See the mix tasks under `Mix.Tasks.Asher.*` and the supporting modules:

    * `Asher.Repos` / `Asher.Manifest` — the tracked-repo manifest
    * `Asher.Github` / `Asher.Git` — GitHub (`gh`) and git operations
    * `Asher.Survey` — the interactive `asher.init` survey
    * `Asher.Contribution` — slug/branch/folder naming and the `data/` receipt
  """
end
