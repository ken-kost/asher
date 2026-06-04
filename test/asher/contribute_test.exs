defmodule Asher.ContributeTest do
  # async: false — the prepare/publish tests stub the global shell.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Asher.Contribute
  alias Asher.Test.StubShell

  defp survey(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "Add upsert support"),
      slug: Keyword.get(opts, :slug, "add-upsert-support"),
      category: Keyword.get(opts, :category, "bug fix"),
      repos:
        Keyword.get(opts, :repos, [
          %{"org" => "ash-project", "name" => "ash", "full_name" => "ash-project/ash"}
        ]),
      issue:
        Keyword.get(opts, :issue, %{
          org: "ash-project",
          repo: "ash",
          full_name: "ash-project/ash",
          number: 42,
          url: "https://github.com/ash-project/ash/issues/42"
        }),
      scraped: Keyword.get(opts, :scraped, %{"labels" => ["bug"]})
    }
  end

  defp at(body, substr), do: :binary.match(body, substr) |> elem(0)

  describe "prepare/2 and publish_one/3 (stubbed shell)" do
    setup do
      on_exit(&StubShell.reset/0)

      StubShell.stub(fn
        "gh", ["repo", "view" | _], _ ->
          {"main", 0}

        "gh", ["pr", "create" | rest], _ ->
          send(self(), {:pr_create, rest})
          {"https://github.com/ash-project/ash/pull/7\n", 0}

        "git", ["-C", _, "rev-list", "--count" | _], _ ->
          {"1", 0}

        _bin, _args, _opts ->
          {"", 0}
      end)
    end

    test "prepare returns a prepared status per repo (no PR)" do
      s = %{
        category: "bug fix",
        slug: "x",
        repos: [%{"org" => "ash-project", "name" => "ash", "full_name" => "ash-project/ash"}]
      }

      capture_io(fn -> send(self(), {:res, Contribute.prepare(s, "ken")}) end)
      assert_received {:res, results}

      assert results["ash-project/ash"]["status"] == "prepared"
      assert results["ash-project/ash"]["branch"] == "fix/x"
      refute_received {:pr_create, _}
    end

    test "publish_one pushes and opens a ready (non-draft) PR" do
      entry = %{"org" => "ash-project", "name" => "ash", "full_name" => "ash-project/ash"}

      capture_io(fn ->
        info =
          Contribute.publish_one(entry, "ken",
            branch: "fix/x",
            title: "fix: X",
            body: "b",
            draft: false
          )

        send(self(), {:res, info})
      end)

      assert_received {:res, info}
      assert info["status"] == "open"
      assert info["pr_url"] == "https://github.com/ash-project/ash/pull/7"
      assert info["draft"] == false
      assert_received {:pr_create, rest}
      refute "--draft" in rest
    end
  end

  describe "pr_title/1 — category-prefixed" do
    test "prefixes the title with the category's commit prefix" do
      assert Contribute.pr_title(survey(category: "bug fix")) == "fix: Add upsert support"

      assert Contribute.pr_title(survey(category: "feature", name: "New thing")) ==
               "feat: New thing"

      assert Contribute.pr_title(survey(category: "test", name: "Cover X")) == "test: Cover X"
    end

    test "a custom category becomes its own prefix" do
      assert Contribute.pr_title(survey(category: "perf", name: "Speed up")) == "perf: Speed up"
    end
  end

  describe "pr_body/2 — ash-project contributor template" do
    test "owning repo: `Closes #n` first, then the checklist, then details" do
      s = survey()
      body = Contribute.pr_body(s, hd(s.repos))

      assert String.starts_with?(body, "Closes #42\n")
      assert body =~ "# Contributor checklist"
      assert body =~ "Leave anything that you believe does not apply unchecked."

      assert body =~
               "- [ ] I accept the [AI Policy](https://github.com/ash-project/.github/blob/main/AI_POLICY.md), or AI was not used in the creation of this PR."

      assert body =~ "- [ ] Bug fixes include regression tests"
      assert body =~ "- [ ] Chores"
      assert body =~ "- [ ] Documentation changes"
      assert body =~ "- [ ] Features include unit/acceptance tests"
      assert body =~ "- [ ] Refactoring"
      assert body =~ "- [ ] Update dependencies"
      assert body =~ "**Category:** bug fix"
      assert body =~ "ash-project/ash"

      assert at(body, "Closes #42") < at(body, "# Contributor checklist")
      assert at(body, "# Contributor checklist") < at(body, "## Details")
    end

    test "non-owning repo links the issue instead of closing it" do
      s =
        survey(
          repos: [
            %{"org" => "ash-project", "name" => "ash_sql", "full_name" => "ash-project/ash_sql"}
          ]
        )

      body = Contribute.pr_body(s, hd(s.repos))

      refute body =~ "Closes #42"

      assert String.starts_with?(
               body,
               "Related issue: https://github.com/ash-project/ash/issues/42\n"
             )

      assert body =~ "# Contributor checklist"
    end

    test "no issue: body starts with the checklist" do
      s = survey(issue: nil, scraped: nil)
      body = Contribute.pr_body(s, hd(s.repos))

      assert String.starts_with?(body, "# Contributor checklist")
      assert body =~ "**Labels:** —"
    end

    test "every checklist item is left unchecked for the contributor" do
      body = Contribute.pr_body(survey(), %{"full_name" => "ash-project/ash"})
      refute body =~ "- [x]"
      assert length(String.split(body, "- [ ] ")) == 8
    end
  end
end
