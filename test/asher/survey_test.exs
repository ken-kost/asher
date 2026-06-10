defmodule Asher.SurveyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Asher.Survey
  alias Asher.Test.StubShell

  @repos [
    %{
      "org" => "ash-project",
      "name" => "ash",
      "full_name" => "ash-project/ash",
      "description" => "core"
    },
    %{
      "org" => "ash-project",
      "name" => "ash_postgres",
      "full_name" => "ash-project/ash_postgres",
      "description" => "pg"
    }
  ]

  setup do
    on_exit(&StubShell.reset/0)
    :ok
  end

  defp issue_payload do
    Jason.encode!(%{
      "title" => "Fix the bug",
      "body" => "details",
      "state" => "open",
      "number" => 42,
      "url" => "https://github.com/ash-project/ash/issues/42",
      "labels" => [%{"name" => "bug"}],
      "author" => %{"login" => "x"}
    })
  end

  defp run(input, repos \\ @repos) do
    capture_io(input, fn -> Process.put(:survey, Survey.run(repos)) end)
    Process.get(:survey)
  end

  test "with an issue: scrapes it, pre-selects category, prefills repo, suggests name" do
    StubShell.stub(fn "gh", ["issue", "view", "42" | _], _ -> {issue_payload(), 0} end)

    # y → issue url → (empty = default category "bug fix") → 0 (done, ash prefilled) → (empty = default name)
    survey = run("y\nhttps://github.com/ash-project/ash/issues/42\n\n0\n\n")

    assert survey.issue.number == 42
    assert survey.issue.full_name == "ash-project/ash"
    assert survey.category == "bug fix"
    assert Enum.map(survey.repos, & &1["name"]) == ["ash"]
    assert survey.name == "Fix the bug"
    assert survey.slug == "fix-the-bug"
  end

  test "without an issue: pick category by number, reject empty repo set, multi-select, custom name" do
    StubShell.stub(fn _, _, _ -> {"", 0} end)

    # n → category index 2 (bug fix) → 0 (done with none → rejected) → 1 (ash) → 1 (ash_postgres; last one auto-finishes) → name
    survey = run("n\n2\n0\n1\n1\nCustom Name\n")

    assert survey.issue == nil
    assert survey.scraped == nil
    assert survey.category == "fix"
    assert Enum.map(survey.repos, & &1["name"]) == ["ash", "ash_postgres"]
    assert survey.name == "Custom Name"
    assert survey.slug == "custom-name"
  end

  test "supports the built-in `test` category and a custom `other` category" do
    StubShell.stub(fn _, _, _ -> {"", 0} end)

    # category index 5 is `test`
    s1 = run("n\n6\n1\n0\nAdd tests\n")
    assert s1.category == "test"

    # index 6 is `other` → next input is the custom category
    s2 = run("n\n7\nperf\n1\n0\nSpeed things up\n")
    assert s2.category == "perf"
    assert Enum.map(s2.repos, & &1["name"]) == ["ash"]
  end

  test "continues gracefully when scraping fails" do
    StubShell.stub(fn "gh", ["issue", "view" | _], _ -> {"not found", 1} end)

    survey = run("y\nhttps://github.com/ash-project/ash/issues/42\n2\n0\nMy thing\n")

    assert survey.issue.number == 42
    assert survey.issue.url == nil
    assert survey.scraped == nil
    assert survey.category == "fix"
    # issue repo (ash) was still prefilled, "0" finishes
    assert Enum.map(survey.repos, & &1["name"]) == ["ash"]
    assert survey.name == "My thing"
  end

  describe "derive_category/1" do
    test "maps common labels" do
      assert Survey.derive_category(%{"labels" => ["bug"]}) == "bug fix"
      assert Survey.derive_category(%{"labels" => ["enhancement"]}) == "enhancement"
      assert Survey.derive_category(%{"labels" => ["documentation"]}) == "documentation"
      assert Survey.derive_category(%{"labels" => ["test"]}) == "test"
      assert Survey.derive_category(%{"labels" => ["feature request"]}) == "feature"
      assert Survey.derive_category(%{"labels" => ["needs-improvement"]}) == "improvement"
    end

    test "nil for unknown or missing labels" do
      assert Survey.derive_category(%{"labels" => ["question"]}) == nil
      assert Survey.derive_category(nil) == nil
    end
  end
end
