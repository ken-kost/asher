defmodule Asher.Console do
  @moduledoc """
  Plain-IO prompts and output.

  asher runs in two contexts — as `mix asher.*` igniter tasks and as a standalone
  `asher` escript — so the survey and progress logging must not depend on igniter
  or `Mix.shell/0`. This module provides `yes?/1` and `select/3` that mirror
  `Igniter.Util.IO`'s semantics (numbered selection, single/empty auto-return,
  `:default`/`:display` options) using `IO.gets/1`, which is drivable from tests
  via `ExUnit.CaptureIO`.
  """

  @doc "Print a line to stdout."
  @spec say(IO.chardata()) :: :ok
  def say(message), do: IO.puts(message)

  @doc "Print a line to stderr."
  @spec warn(IO.chardata()) :: :ok
  def warn(message), do: IO.puts(:stderr, message)

  @doc "Prompt for free-text input, returning the trimmed string (\"\" on EOF)."
  @spec prompt(IO.chardata()) :: String.t()
  def prompt(label) do
    case IO.gets(label) do
      :eof -> ""
      str -> String.trim(to_string(str))
    end
  end

  @doc "Yes/no prompt. Empty defaults to yes; repeats on bad input; raises on EOF."
  @spec yes?(String.t()) :: boolean()
  def yes?(question) do
    case IO.gets(question <> " [Y/n] ") do
      :eof ->
        raise "No input detected when asking for confirmation. Run this in an interactive terminal."

      str ->
        case str |> to_string() |> String.trim() do
          "" -> true
          yes when yes in ~w(y Y yes YES) -> true
          no when no in ~w(n N no NO) -> false
          other -> say("Please answer y or n. Got: #{other}") && yes?(question)
        end
    end
  end

  @doc """
  Select an item from a list by number.

  Mirrors `Igniter.Util.IO.select/3`: returns `nil` for `[]`, auto-returns the
  sole item for a 1-element list (no prompt), and otherwise repeats until a valid
  number is entered. Options: `:display` (item → string) and `:default` (returned
  on empty input).
  """
  @spec select(String.t(), [term()], keyword()) :: term()
  def select(prompt, items, opts \\ [])
  def select(_prompt, [], _opts), do: nil
  def select(_prompt, [item], _opts), do: item

  def select(prompt, items, opts) do
    display = Keyword.get(opts, :display, &to_string/1)

    menu =
      items
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {item, index} ->
        suffix =
          if Keyword.has_key?(opts, :default) and item == opts[:default],
            do: " (default)",
            else: ""

        "#{index}. #{display.(item)}#{suffix}"
      end)

    case IO.gets(prompt <> "\n" <> menu <> "\nInput number ❯ ") do
      :eof ->
        raise "No input detected for selection. Run this in an interactive terminal."

      str ->
        case str |> to_string() |> String.trim() do
          "" -> default_or_retry(prompt, items, opts)
          input -> parse_choice(input, prompt, items, opts)
        end
    end
  end

  defp default_or_retry(prompt, items, opts) do
    case Keyword.fetch(opts, :default) do
      {:ok, value} -> value
      :error -> select(prompt, items, opts)
    end
  end

  defp parse_choice(input, prompt, items, opts) do
    case Integer.parse(input) do
      {index, ""} when index >= 0 ->
        case Enum.at(items, index) do
          nil ->
            say("Expected one of the listed numbers. Got: #{input}")
            select(prompt, items, opts)

          value ->
            value
        end

      _ ->
        say("Expected a number. Got: #{input}")
        select(prompt, items, opts)
    end
  end
end
