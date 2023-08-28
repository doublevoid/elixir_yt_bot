defmodule ElixirYtBotTest do
  use ExUnit.Case
  doctest ElixirYtBot

  test "greets the world" do
    assert ElixirYtBot.hello() == :world
  end
end
