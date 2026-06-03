defmodule Asher.ConsoleTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Asher.Console

  defp with_input(input, fun) do
    capture_io(input, fn -> Process.put(:result, fun.()) end)
    Process.get(:result)
  end

  describe "yes?/1" do
    test "empty defaults to true; parses y/yes/n/no" do
      assert with_input("\n", fn -> Console.yes?("ok?") end) == true
      assert with_input("y\n", fn -> Console.yes?("ok?") end) == true
      assert with_input("yes\n", fn -> Console.yes?("ok?") end) == true
      assert with_input("n\n", fn -> Console.yes?("ok?") end) == false
      assert with_input("no\n", fn -> Console.yes?("ok?") end) == false
    end

    test "repeats on unrecognized input" do
      assert with_input("maybe\ny\n", fn -> Console.yes?("ok?") end) == true
    end
  end

  describe "select/3" do
    test "returns nil for [] and auto-returns the sole item without prompting" do
      assert Console.select("pick", []) == nil
      assert Console.select("pick", [:only]) == :only
    end

    test "returns the chosen item by 0-based index" do
      assert with_input("1\n", fn -> Console.select("pick", [:a, :b, :c]) end) == :b
    end

    test "uses :default on empty input" do
      assert with_input("\n", fn -> Console.select("pick", [:a, :b], default: :b) end) == :b
    end

    test "repeats on out-of-range, negative, or non-numeric input" do
      assert with_input("9\n-1\nx\n0\n", fn -> Console.select("pick", [:a, :b]) end) == :a
    end

    test "applies the :display function" do
      out = capture_io("0\n", fn -> Console.select("pick", [%{n: "ash"}], display: & &1.n) end)
      # single-item lists auto-return; use two items to force the menu
      out2 =
        capture_io("0\n", fn ->
          Console.select("pick", [%{n: "ash"}, %{n: "spark"}], display: & &1.n)
        end)

      assert out == ""
      assert out2 =~ "ash"
      assert out2 =~ "spark"
    end
  end

  test "prompt/1 trims input" do
    assert with_input("  hi \n", fn -> Console.prompt("> ") end) == "hi"
  end
end
