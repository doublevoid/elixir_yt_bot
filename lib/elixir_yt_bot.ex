defmodule AudioPlayerSupervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [AudioPlayerConsumer, AudioPlayerConsumer.State]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule AudioPlayerConsumer do
  use Nostrum.Consumer

  alias Nostrum.Api
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Voice

  require Logger

  # Compile-time helper for defining Discord Application Command options
  opt = fn type, name, desc, opts ->
    %{type: type, name: name, description: desc}
    |> Map.merge(Enum.into(opts, %{}))
  end

  @play_opts [
    opt.(1, "url", "Play a URL from a common service",
      options: [opt.(3, "url", "URL to play", required: true)]
    )
  ]

  @commands [
    {"leave", "Tell bot to leave your voice channel", []},
    {"play", "Play a sound", @play_opts},
    {"stop", "Stop the playing sound", []},
    {"pause", "Pause the playing sound", []},
    {"resume", "Resume the paused sound", []}
  ]

  def get_voice_channel_of_interaction(%{guild_id: guild_id, user: %{id: user_id}} = _interaction) do
    guild_id
    |> GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == user_id end)
    |> Map.get(:channel_id)
  end

  # If you are running this example in an iex session where you manually call
  # AudioPlayerSupervisor.start_link, you will have to call this function
  # with your guild_id as the argument
  def create_guild_commands(guild_id) do
    Enum.each(@commands, fn {name, description, options} ->
      Api.create_guild_application_command(guild_id, %{
        name: name,
        description: description,
        options: options
      })
    end)
  end

  @spec handle_event(any) ::
          :noop | :ok | {:ok} | {:error, %{response: binary | map, status_code: 1..1_114_111}}
  def handle_event({:READY, %{guilds: guilds} = _event, _ws_state}) do
    guilds
    |> Enum.map(fn guild -> guild.id end)
    |> Enum.each(&create_guild_commands/1)
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    # Run the command, and check for a response message, or default to a checkmark emoji
    message =
      case do_command(interaction) do
        {:msg, msg} -> msg
        _ -> "done"
      end

    Api.create_interaction_response(interaction, %{type: 4, data: %{content: message}})
  end

  def handle_event({:VOICE_SPEAKING_UPDATE, payload, _ws_state}) do
    if payload.speaking == false && payload.timed_out == false do
      first_of_queue = dequeue()
      Voice.play(first_of_queue[:guild_id], first_of_queue[:url], :ytdl)
    end
  end

  def handle_event({:VOICE_READY, _, _}) do
    interaction = AudioPlayerConsumer.State.get(:interaction)

    Voice.play(interaction[:guild_id], interaction[:url], :ytdl)
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  @spec do_command(%{
          :data => %{:name => <<_::32, _::_*8>>, optional(any) => any},
          :guild_id => non_neg_integer,
          optional(any) => any
        }) :: :ok | {:error, <<_::64, _::_*8>>} | {:msg, <<_::160, _::_*184>>}
  def do_command(%{guild_id: guild_id, data: %{name: "summon"}} = interaction) do
    case get_voice_channel_of_interaction(interaction) do
      nil ->
        {:msg, "You must be in a voice channel to summon me"}

      voice_channel_id ->
        Voice.join_channel(guild_id, voice_channel_id, false, true)
    end
  end

  def do_command(%{guild_id: guild_id, data: %{name: "leave"}}) do
    Voice.leave_channel(guild_id)
    {:msg, "See you later :wave:"}
  end

  def do_command(%{guild_id: guild_id, data: %{name: "pause"}}), do: Voice.pause(guild_id)

  def do_command(%{guild_id: guild_id, data: %{name: "resume"}}), do: Voice.resume(guild_id)

  def do_command(%{guild_id: guild_id, data: %{name: "stop"}}), do: Voice.stop(guild_id)

  def do_command(%{guild_id: guild_id, data: %{name: "play", options: options}} = interaction) do
    url_option = Enum.at(options, 0).options |> Enum.at(0)
    url = url_option.value

    cond do
      Voice.playing?(guild_id) ->
        enqueue(guild_id, url)

      !Voice.ready?(guild_id) ->
        case get_voice_channel_of_interaction(interaction) do
          nil ->
            {:msg, "You must be in a voice channel to summon me"}

          voice_channel_id ->
            Voice.join_channel(guild_id, voice_channel_id, false, true)
        end

        AudioPlayerConsumer.State.put(:interaction, %{
          guild_id: guild_id,
          url: url
        })

      true ->
        Voice.play(guild_id, url, :ytdl)
    end
  end

  defp enqueue(guild_id, url) do
    current_queue = AudioPlayerConsumer.State.get(:queue) || []
    AudioPlayerConsumer.State.put(:queue, current_queue ++ [%{guild_id: guild_id, url: url}])
  end

  defp dequeue do
    {first_of_queue, new_queue} = List.pop_at(AudioPlayerConsumer.State.get(:queue), 0)
    AudioPlayerConsumer.State.put(:queue, new_queue)
    first_of_queue
  end
end

defmodule AudioPlayerConsumer.State do
  use Agent
  require Logger

  def start_link(_args) do
    Agent.start_link(fn -> %{} end, name: :audio_player_consumer_state)
  end

  def put(key, data) do
    Agent.update(:audio_player_consumer_state, fn state ->
      Map.put(state, key, data)
    end)
  end

  @spec get(any) :: any
  def get(key) do
    Agent.get(:audio_player_consumer_state, fn state ->
      Map.get(state, key)
    end)
  end
end
