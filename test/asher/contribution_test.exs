defmodule Asher.ContributionTest do
  use ExUnit.Case, async: true

  alias Asher.Contribution

  describe "slugify/1" do
    test "lowercases and hyphenates" do
      assert Contribution.slugify("Add Upsert Support") == "add-upsert-support"
    end

    test "collapses punctuation and trims" do
      assert Contribution.slugify("  Fix: the (broken) thing!! ") == "fix-the-broken-thing"
    end

    test "drops non-ascii letters to hyphens" do
      assert Contribution.slugify("Café résumé") == "caf-r-sum"
    end

    test "caps length" do
      assert String.length(Contribution.slugify(String.duplicate("a", 200))) <= 60
    end

    test "falls back when empty" do
      assert Contribution.slugify("!!!") == "contribution"
      assert Contribution.slugify("") == "contribution"
    end
  end

  describe "category_prefix/1 and branch_name/2" do
    test "maps every category to a git-friendly prefix" do
      assert Contribution.category_prefix("feature") == "feat"
      assert Contribution.category_prefix("enhancement") == "enhance"
      assert Contribution.category_prefix("bug fix") == "fix"
      assert Contribution.category_prefix("improvement") == "improve"
      assert Contribution.category_prefix("documentation") == "docs"
      assert Contribution.category_prefix("test") == "test"
    end

    test "custom categories are slugified into their own prefix" do
      assert Contribution.category_prefix("perf") == "perf"
      assert Contribution.category_prefix("My Custom Category") == "my-custom-category"
    end

    test "`test` is a built-in category" do
      assert "test" in Contribution.categories()
    end

    test "branch_name combines prefix and slug" do
      assert Contribution.branch_name("bug fix", "broken-thing") == "fix/broken-thing"
    end
  end

  test "folder_name formats slug and slash-free repo names" do
    assert Contribution.folder_name("add-x", ["ash", "ash_sql"]) == "add-x (ash, ash_sql)"
  end

  describe "metadata_map/4 and render_markdown/1" do
    setup do
      survey = %{
        name: "Add X",
        slug: "add-x",
        category: "feature",
        repos: [%{"org" => "ash-project", "name" => "ash", "full_name" => "ash-project/ash"}],
        issue: %{
          org: "ash-project",
          repo: "ash",
          full_name: "ash-project/ash",
          number: 7,
          url: "https://x/7"
        },
        scraped: %{"title" => "Add X", "labels" => ["enhancement"], "state" => "open"}
      }

      results = %{
        "ash-project/ash" => %{status: "ok", pr_url: "https://pr/1", branch: "feat/add-x"}
      }

      %{meta: Contribution.metadata_map(survey, "ken", results, false)}
    end

    test "captures the gathered data", %{meta: meta} do
      assert meta["name"] == "Add X"
      assert meta["branch"] == "feat/add-x"
      assert meta["fork_owner"] == "ken"
      assert meta["dry_run"] == false
      assert meta["issue"]["number"] == 7
      assert meta["scraped"]["labels"] == ["enhancement"]
      assert meta["results"]["ash-project/ash"]["pr_url"] == "https://pr/1"
      assert meta["results"]["ash-project/ash"]["status"] == "ok"
      assert is_binary(meta["created_at"])
    end

    test "json-round-trips (jason-encodable)", %{meta: meta} do
      assert {:ok, decoded} = Jason.decode(Jason.encode!(meta))
      assert decoded["branch"] == "feat/add-x"
    end

    test "render_markdown includes branch and PR link", %{meta: meta} do
      md = Contribution.render_markdown(meta)
      assert md =~ "# Add X"
      assert md =~ "feat/add-x"
      assert md =~ "https://pr/1"
      assert md =~ "ash-project/ash"
    end

    test "render_markdown marks dry runs and missing PRs" do
      survey = %{
        name: "Doc tweak",
        slug: "doc-tweak",
        category: "documentation",
        repos: [%{"org" => "ash-project", "name" => "ash", "full_name" => "ash-project/ash"}],
        issue: nil,
        scraped: nil
      }

      meta = Contribution.metadata_map(survey, nil, %{}, true)
      md = Contribution.render_markdown(meta)
      assert md =~ "_(dry run)_"
      assert md =~ "No linked issue"
    end
  end
end
