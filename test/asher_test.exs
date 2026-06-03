defmodule AsherTest do
  use ExUnit.Case
  doctest Asher

  test "greets the world" do
    assert Asher.hello() == :world
  end
end
