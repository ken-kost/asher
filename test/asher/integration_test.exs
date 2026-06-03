defmodule Asher.IntegrationTest do
  @moduledoc """
  Live, read-only checks against the public GitHub API. Excluded by default;
  run with `mix test --include integration`.
  """
  use ExUnit.Case, async: false

  alias Asher.Repos

  @moduletag :integration

  test "fetches and filters the real ash-project org" do
    assert {:ok, raw} = Asher.Github.fetch_org_repos("ash-project")
    assert is_list(raw) and length(raw) > 40

    entries = Repos.filter(raw, "ash-project", lang: "elixir")
    names = Enum.map(entries, & &1["name"])

    # flagship repos are present
    assert "ash" in names
    assert "ash_postgres" in names
    assert "igniter" in names

    # archived / forks / .github are filtered out
    refute ".github" in names
    refute Enum.any?(entries, &(&1["archived"] or &1["fork"]))

    # entries carry the org and full_name
    assert Enum.all?(entries, &(&1["org"] == "ash-project"))
    assert "ash-project/ash" in Enum.map(entries, & &1["full_name"])
  end
end
