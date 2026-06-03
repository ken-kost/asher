defmodule Asher.Tasks do
  @moduledoc "Small helpers shared by the asher mix tasks."

  @doc """
  Normalize igniter `--lang/--include/--exclude` options into the keyword shape
  `Asher.Repos.filter/3` expects (`:lang` string, `:include`/`:exclude` lists).
  """
  @spec parse_filter_opts(keyword()) :: keyword()
  def parse_filter_opts(options) do
    [
      lang: options[:lang],
      include: split_csv(options[:include]),
      exclude: split_csv(options[:exclude])
    ]
  end

  defp split_csv(nil), do: []
  defp split_csv(value), do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
end
