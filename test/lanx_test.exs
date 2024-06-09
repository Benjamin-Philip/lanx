defmodule LanxTest do
  use ExUnit.Case
  doctest Lanx

  test "greets the world" do
    assert Lanx.hello() == :world
  end
end
