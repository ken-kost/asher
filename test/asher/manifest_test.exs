defmodule Asher.ManifestTest do
  use ExUnit.Case, async: true

  alias Asher.Manifest

  test "render_block lists each repo dir between markers" do
    block = Manifest.render_block(["ash", "ash_postgres"])
    assert block =~ "# === asher: cloned org repos (managed; see priv/repos.json) ==="
    assert block =~ "/ash/\n"
    assert block =~ "/ash_postgres/\n"
    assert block =~ "# === end asher clones ==="
  end

  test "changes/2 returns igniter-free {path, content} for manifest + gitignore" do
    entry = %{
      "org" => "acme",
      "name" => "widget",
      "full_name" => "acme/widget",
      "clone_url" => "https://github.com/acme/widget.git",
      "url" => "https://github.com/acme/widget",
      "description" => "a widget",
      "language" => "Elixir",
      "archived" => false,
      "fork" => false
    }

    {merged, changes} = Manifest.changes("acme", [entry])
    paths = Enum.map(changes, &elem(&1, 0))

    assert "priv/repos.json" in paths
    assert ".gitignore" in paths
    assert Enum.any?(merged, &(&1["full_name"] == "acme/widget"))

    json = changes |> List.keyfind("priv/repos.json", 0) |> elem(1)
    assert json =~ "acme/widget"

    gitignore = changes |> List.keyfind(".gitignore", 0) |> elem(1)
    assert gitignore =~ "/widget/"
  end

  describe "replace_block/2" do
    test "appends a new block when none exists" do
      existing = "/_build/\n/deps/\n"
      block = Manifest.render_block(["ash"])
      result = Manifest.replace_block(existing, block)

      assert result =~ "/_build/"
      assert result =~ "/ash/"
      assert String.contains?(result, block)
    end

    test "replaces an existing managed block in place (idempotent)" do
      existing = "/_build/\n"
      result1 = Manifest.replace_block(existing, Manifest.render_block(["ash"]))
      result2 = Manifest.replace_block(result1, Manifest.render_block(["ash", "spark"]))

      # old single-repo block is gone, new one is present, only one managed block
      refute result2 =~ "/ash/\n# === end"
      assert result2 =~ "/spark/"
      assert length(String.split(result2, "# === end asher clones ===")) == 2
      assert result2 =~ "/_build/"
    end
  end
end
