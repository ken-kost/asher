defmodule Asher.GithubTest do
  use ExUnit.Case, async: false

  alias Asher.Github
  alias Asher.Test.StubShell

  setup do
    on_exit(&StubShell.reset/0)
    :ok
  end

  describe "parse_org/1 (pure)" do
    test "accepts slugs, URLs and org paths" do
      assert Github.parse_org("ash-project") == "ash-project"
      assert Github.parse_org("https://github.com/ash-project") == "ash-project"
      assert Github.parse_org("github.com/ash-project") == "ash-project"
      assert Github.parse_org("https://github.com/orgs/ash-project/repositories") == "ash-project"
      assert Github.parse_org("https://github.com/ash-project/") == "ash-project"
    end

    test "defaults to ash-project when blank" do
      assert Github.parse_org(nil) == "ash-project"
      assert Github.parse_org("  ") == "ash-project"
    end
  end

  describe "parse_issue_ref/1 (pure)" do
    test "parses full issue and pull URLs" do
      assert {:ok, %{org: "ash-project", repo: "ash", number: 42}} =
               Github.parse_issue_ref("https://github.com/ash-project/ash/issues/42")

      assert {:ok, %{org: "ash-project", repo: "ash_postgres", number: 7}} =
               Github.parse_issue_ref("https://github.com/ash-project/ash_postgres/pull/7")
    end

    test "parses the org/repo#n shorthand" do
      assert {:ok, %{org: "ash-project", repo: "ash", number: 3}} =
               Github.parse_issue_ref("ash-project/ash#3")
    end

    test "rejects nonsense" do
      assert {:error, _} = Github.parse_issue_ref("not a ref")
      assert {:error, _} = Github.parse_issue_ref("https://github.com/ash-project/ash")
    end
  end

  describe "view_issue/3 (stubbed gh)" do
    test "normalizes the gh json payload" do
      payload =
        Jason.encode!(%{
          "title" => "Fix the bug",
          "body" => "details",
          "state" => "OPEN",
          "number" => 42,
          "url" => "https://github.com/ash-project/ash/issues/42",
          "labels" => [%{"name" => "bug"}, %{"name" => "area:core"}],
          "author" => %{"login" => "someone"}
        })

      StubShell.stub(fn "gh", ["issue", "view", "42" | _], _ -> {payload, 0} end)

      assert {:ok, issue} = Github.view_issue("ash-project", "ash", 42)
      assert issue["title"] == "Fix the bug"
      assert issue["labels"] == ["bug", "area:core"]
      assert issue["author"] == "someone"
    end

    test "surfaces gh errors" do
      StubShell.stub(fn "gh", _, _ -> {"could not find issue", 1} end)
      assert {:error, "could not find issue"} = Github.view_issue("ash-project", "ash", 999)
    end
  end

  describe "fetch_org_repos/1 (stubbed curl, paginated)" do
    test "returns a single short page" do
      page = Jason.encode!([%{"name" => "ash"}, %{"name" => "spark"}])
      StubShell.stub(fn "curl", _, _ -> {page, 0} end)

      assert {:ok, [%{"name" => "ash"}, %{"name" => "spark"}]} =
               Github.fetch_org_repos("ash-project")
    end

    test "follows pagination until a short page" do
      page1 = Jason.encode!(Enum.map(1..100, &%{"name" => "r#{&1}"}))
      page2 = Jason.encode!([%{"name" => "last"}])

      # NB: the URL contains `per_page=100`, so match the trailing `&page=2`
      # explicitly rather than the substring `page=1`.
      StubShell.stub(fn "curl", args, _ ->
        url = List.last(args)
        if String.contains?(url, "&page=2"), do: {page2, 0}, else: {page1, 0}
      end)

      assert {:ok, repos} = Github.fetch_org_repos("ash-project")
      assert length(repos) == 101
      assert List.last(repos)["name"] == "last"
    end

    test "reports API error messages" do
      StubShell.stub(fn "curl", _, _ -> {Jason.encode!(%{"message" => "Not Found"}), 0} end)
      assert {:error, msg} = Github.fetch_org_repos("nope")
      assert msg =~ "Not Found"
    end
  end

  describe "ensure_fork/3 (stubbed gh, idempotent)" do
    test "ok on success and on already-exists" do
      StubShell.stub(fn "gh", ["repo", "fork" | _], _ -> {"", 0} end)
      assert :ok = Github.ensure_fork("ash-project", "ash", "ken")

      StubShell.stub(fn "gh", ["repo", "fork" | _], _ -> {"a fork already exists", 1} end)
      assert :ok = Github.ensure_fork("ash-project", "ash", "ken")
    end

    test "error on real failure" do
      StubShell.stub(fn "gh", _, _ -> {"boom", 1} end)
      assert {:error, "boom"} = Github.ensure_fork("ash-project", "ash", "ken")
    end
  end

  describe "ensure_draft_pr/7 (stubbed gh, idempotent)" do
    test "returns the created PR url" do
      StubShell.stub(fn "gh", ["pr", "create" | _], _ ->
        {"Creating draft pull request\nhttps://github.com/ash-project/ash/pull/123\n", 0}
      end)

      assert {:ok, "https://github.com/ash-project/ash/pull/123"} =
               Github.ensure_draft_pr("ash-project", "ash", "ken", "fix/x", "main", "t", "b")
    end

    test "looks up the existing PR when one already exists" do
      StubShell.stub(fn
        "gh", ["pr", "create" | _], _ -> {"a pull request already exists", 1}
        "gh", ["pr", "list" | _], _ -> {"https://github.com/ash-project/ash/pull/9", 0}
      end)

      assert {:ok, "https://github.com/ash-project/ash/pull/9"} =
               Github.ensure_draft_pr("ash-project", "ash", "ken", "fix/x", "main", "t", "b")
    end
  end

  describe "auth/identity (stubbed gh)" do
    test "ensure_authed! maps exit status" do
      StubShell.stub(fn "gh", ["auth", "status"], _ -> {"logged in", 0} end)
      assert :ok = Github.ensure_authed!()

      StubShell.stub(fn "gh", ["auth", "status"], _ -> {"not logged in", 1} end)
      assert {:error, msg} = Github.ensure_authed!()
      assert msg =~ "gh auth login"
    end

    test "current_user trims the login" do
      StubShell.stub(fn "gh", ["api", "user" | _], _ -> {"ken\n", 0} end)
      assert {:ok, "ken"} = Github.current_user()
    end

    test "default_branch falls back to main" do
      StubShell.stub(fn "gh", ["repo", "view" | _], _ -> {"", 1} end)
      assert Github.default_branch("ash-project", "ash") == "main"

      StubShell.stub(fn "gh", ["repo", "view" | _], _ -> {"master\n", 0} end)
      assert Github.default_branch("ash-project", "ash") == "master"
    end
  end
end
