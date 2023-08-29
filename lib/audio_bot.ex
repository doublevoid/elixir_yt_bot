defmodule AudioBot do
  use Application

  def start(_type, _args) do
    AudioPlayerSupervisor.start_link([])
  end
end
