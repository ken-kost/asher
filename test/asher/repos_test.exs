defmodule Asher.ReposTest do
  use ExUnit.Case, async: true

  alias Asher.Repos

  defp raw(name, attrs \\ %{}) do
    Map.merge(
      %{
        "name" => name,
        "html_url" => "https://github.com/ash-project/#{name}",
        "clone_url" => "https://github.com/ash-project/#{name}.git",
        "description" => "desc #{name}",
        "language" => "Elixir",
        "archived" => false,
        "fork" => false
      },
      attrs
    )
  end

  describe "keep?/2" do
    test "keeps active repos by default" do
      assert Repos.keep?(raw("ash"), [])
    end

    test "drops archived, forks and .github" do
      refute Repos.keep?(raw("ash_blog", %{"archived" => true}), [])
      refute Repos.keep?(raw("ash_dashboard", %{"fork" => true}), [])
      refute Repos.keep?(raw(".github"), [])
    end

    test "language filter is case-insensitive" do
      assert Repos.keep?(raw("ash"), lang: "elixir")
      refute Repos.keep?(raw("igniter_js", %{"language" => "Rust"}), lang: "elixir")
      refute Repos.keep?(raw("weird", %{"language" => nil}), lang: "elixir")
    end

    test "include overrides filters, exclude overrides everything" do
      assert Repos.keep?(raw("ash_hq", %{"language" => "HTML"}),
               lang: "elixir",
               include: ["ash_hq"]
             )

      refute Repos.keep?(raw("ash"), exclude: ["ash"])
      # exclude wins even over include
      refute Repos.keep?(raw("ash"), include: ["ash"], exclude: ["ash"])
    end
  end

  describe "filter/3" do
    test "normalizes kept repos into manifest entries, sorted by name" do
      raw = [raw("ash_postgres"), raw("ash"), raw("ash_blog", %{"archived" => true})]
      entries = Repos.filter(raw, "ash-project", [])

      assert Enum.map(entries, & &1["name"]) == ["ash", "ash_postgres"]
      [ash | _] = entries
      assert ash["org"] == "ash-project"
      assert ash["full_name"] == "ash-project/ash"
      assert ash["clone_url"] == "https://github.com/ash-project/ash.git"
      assert ash["url"] == "https://github.com/ash-project/ash"
    end
  end

  describe "merge/3" do
    test "replaces a single org's entries and sorts by full_name" do
      existing = [
        %{"org" => "ash-project", "full_name" => "ash-project/ash", "name" => "ash"},
        %{"org" => "other", "full_name" => "other/thing", "name" => "thing"}
      ]

      fresh = [
        %{"org" => "ash-project", "full_name" => "ash-project/ash_sql", "name" => "ash_sql"}
      ]

      merged = Repos.merge(existing, "ash-project", fresh)

      assert Enum.map(merged, & &1["full_name"]) == ["ash-project/ash_sql", "other/thing"]
    end

    test "appends a brand-new org without dropping others" do
      existing = [%{"org" => "ash-project", "full_name" => "ash-project/ash", "name" => "ash"}]
      fresh = [%{"org" => "acme", "full_name" => "acme/widget", "name" => "widget"}]
      merged = Repos.merge(existing, "acme", fresh)

      assert Enum.map(merged, & &1["full_name"]) == ["acme/widget", "ash-project/ash"]
    end
  end
end
