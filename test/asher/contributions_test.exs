defmodule Asher.ContributionsTest do
  use ExUnit.Case, async: true

  alias Asher.Contributions

  test "to_survey reconstructs a survey-shaped map (issue keys become atoms)" do
    meta = %{
      "name" => "Add X",
      "slug" => "add-x",
      "category" => "bug fix",
      "repos" => [%{"org" => "ash-project", "name" => "ash", "full_name" => "ash-project/ash"}],
      "issue" => %{
        "org" => "ash-project",
        "repo" => "ash",
        "full_name" => "ash-project/ash",
        "number" => 7,
        "url" => "u"
      },
      "scraped" => %{"labels" => ["bug"]}
    }

    s = Contributions.to_survey(meta)

    assert s.name == "Add X"
    assert s.category == "bug fix"
    assert s.issue.number == 7
    assert s.issue.full_name == "ash-project/ash"
    assert hd(s.repos)["full_name"] == "ash-project/ash"
    assert s.scraped["labels"] == ["bug"]
  end

  test "to_survey handles a missing issue" do
    meta = %{
      "name" => "N",
      "slug" => "n",
      "category" => "feature",
      "repos" => [],
      "issue" => nil,
      "scraped" => nil
    }

    assert Contributions.to_survey(meta).issue == nil
  end

  test "put_repo merges into the matching repo entry only" do
    meta = %{
      "repos" => [
        %{"full_name" => "o/a", "status" => "prepared"},
        %{"full_name" => "o/b", "status" => "prepared"}
      ]
    }

    updated = Contributions.put_repo(meta, "o/b", %{"status" => "open", "pr_url" => "u"})

    assert Enum.find(updated["repos"], &(&1["full_name"] == "o/b"))["pr_url"] == "u"
    assert Enum.find(updated["repos"], &(&1["full_name"] == "o/a"))["status"] == "prepared"
  end
end
