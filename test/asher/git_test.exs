defmodule Asher.GitTest do
  use ExUnit.Case, async: false

  alias Asher.Git
  alias Asher.Test.StubShell

  setup do
    on_exit(&StubShell.reset/0)
    :ok
  end

  test "ensure_commit makes an empty commit only when the branch has no work" do
    StubShell.stub(fn
      "git", ["-C", _, "rev-list", "--count" | _], _ ->
        {"0", 0}

      "git", ["-C", _, "commit" | rest], _ ->
        send(self(), {:commit, rest})
        {"[fix/x abc0000] msg", 0}

      _bin, _args, _opts ->
        {"", 0}
    end)

    assert {:ok, _} = Git.ensure_commit("ash", "main", "fix/x", "msg")
    assert_received {:commit, rest}
    assert "--allow-empty" in rest
  end

  test "ensure_commit is a no-op when the branch already has commits" do
    StubShell.stub(fn
      "git", ["-C", _, "rev-list", "--count" | _], _ ->
        {"3", 0}

      "git", ["-C", _, "commit" | _], _ ->
        send(self(), :committed)
        {"", 0}

      _bin, _args, _opts ->
        {"", 0}
    end)

    assert {:ok, :has_commits} = Git.ensure_commit("ash", "main", "fix/x", "msg")
    refute_received :committed
  end
end
