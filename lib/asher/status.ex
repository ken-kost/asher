defmodule Asher.Status do
  @moduledoc """
  Reads the `data/*/contribution.json` receipts and prints a dashboard of
  in-flight contributions. Shared by `mix asher.status` and `asher status`.
  """

  alias Asher.{Console, Workspace}

  @doc "Print the contributions dashboard."
  @spec print() :: :ok
  def print do
    case receipts() do
      [] ->
        Console.say(
          "No contributions recorded yet. Start one with `asher init` (or `mix asher.init`)."
        )

      paths ->
        Console.say("Contributions (#{length(paths)}):\n")
        Enum.each(paths, &print_one/1)
    end
  end

  defp receipts do
    [Workspace.data_root(), "*", "contribution.json"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp print_one(path) do
    with {:ok, json} <- File.read(path),
         {:ok, meta} <- Jason.decode(json) do
      Console.say("• #{meta["name"]} [#{meta["category"]}]#{dry(meta)}")
      Console.say("    branch: #{meta["branch"]}")
      Console.say("    repos:  #{Enum.map_join(meta["repos"] || [], ", ", & &1["full_name"])}")

      Enum.each(meta["results"] || %{}, fn {full, r} ->
        Console.say("    #{full}: #{r["pr_url"] || r["status"]}")
      end)

      Console.say("")
    else
      _ -> Console.warn("• (could not read #{path})")
    end
  end

  defp dry(%{"dry_run" => true}), do: " (dry run)"
  defp dry(_), do: ""
end
