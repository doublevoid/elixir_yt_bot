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

  alias Nostrum.{Api, Cache.GuildCache, Voice}
  require Logger

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
    {"resume", "Resume the paused sound", []},
    {"skip", "Skips the currently playing song and play the next one on the queue", []},
    {"queue", "Gets the current song queue", []},
    {"promote", "Promote a song from the queue",
     [
       opt.(1, "index", "Promote given index from the queue",
         options: [opt.(3, "index", "index of the song in the queue", required: true)]
       )
     ]}
  ]

  def handle_event({:READY, %{guilds: guilds}, _ws_state}) do
    guilds
    |> Enum.map(& &1.id)
    |> Enum.each(&create_guild_commands/1)
  end

  def handle_event({:INTERACTION_CREATE, %{data: %{name: command_name}} = interaction, _ws_state}) do
    message =
      case do_command(command_name, interaction) do
        {:msg, msg} -> msg
        _ -> "done"
      end

    Api.create_interaction_response(interaction, %{type: 4, data: %{content: message}})
  end

  def handle_event(
        {:VOICE_SPEAKING_UPDATE, %{speaking: false, timed_out: false} = _payload, ws_state}
      ) do
    first_of_queue = dequeue(ws_state.guild_id)
    Voice.play(first_of_queue[:guild_id], first_of_queue[:url], :ytdl)
  end

  def handle_event({:VOICE_READY, _, _}) do
    interaction = AudioPlayerConsumer.State.get(:interaction)

    Voice.play(interaction[:guild_id], interaction[:url], :ytdl)
  end

  def handle_event(_), do: :noop

  def do_command("summon", interaction) do
    case get_voice_channel_of_interaction(interaction) do
      nil -> {:msg, "You must be in a voice channel to summon me"}
      voice_channel_id -> Voice.join_channel(interaction.guild_id, voice_channel_id, false, true)
    end
  end

  def do_command("skip", %{guild_id: guild_id}) do
    if(Voice.playing?(guild_id)) do
      next_to_play = dequeue(guild_id)

      Voice.stop(guild_id)
      Voice.play(next_to_play[:guild_id], next_to_play[:url], :ytdl)
    end
  end

  def do_command("queue", %{guild_id: guild_id}),
    do: {:msg, parse_queue(guild_id)}

  def do_command("promote", %{guild_id: guild_id, data: %{options: options}}) do
    promote_option = parse_option(options)

    Logger.debug("bielpk")
    Logger.debug("#{Map.get(promote_option, :value)}")

    promoted_list =
      Map.get(promote_option, :value)
      |> move_to_start(guild_id)

    AudioPlayerConsumer.State.put(String.to_atom("queue#{guild_id}"), promoted_list)
  end

  def do_command("leave", %{guild_id: guild_id}) do
    AudioPlayerConsumer.State.put(String.to_atom("queue#{guild_id}"), [])

    {:msg, "bye", Voice.leave_channel(guild_id)}
  end

  def do_command("pause", %{guild_id: guild_id}), do: Voice.pause(guild_id)
  def do_command("resume", %{guild_id: guild_id}), do: Voice.resume(guild_id)
  def do_command("stop", %{guild_id: guild_id}), do: Voice.stop(guild_id)

  def do_command("play", %{guild_id: guild_id, data: %{options: options}} = interaction) do
    url_option = parse_option(options)
    url = Map.get(url_option, :value)

    play_sound(guild_id, url, interaction)
  end

  defp play_sound(guild_id, url, interaction) do
    valid_url = UrlValidator.valid?(url)

    cond do
      valid_url == false ->
        {:msg, "Invalid URL"}

      Voice.playing?(guild_id) ->
        enqueue(guild_id, url)

      not Voice.ready?(guild_id) ->
        channel_id = get_voice_channel_of_interaction(interaction)
        unless channel_id, do: {:msg, "You must be in a voice channel to summon me"}
        Voice.join_channel(guild_id, channel_id, false, true)
        AudioPlayerConsumer.State.put(:interaction, %{guild_id: guild_id, url: url})

      true ->
        Voice.play(guild_id, url, :ytdl)
    end
  end

  defp get_voice_channel_of_interaction(%{guild_id: guild_id, user: %{id: user_id}}) do
    guild_id
    |> GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(fn v -> v.user_id == user_id end)
    |> Map.get(:channel_id)
  end

  defp enqueue(guild_id, url) do
    queue = AudioPlayerConsumer.State.get(String.to_atom("queue#{guild_id}")) || []

    AudioPlayerConsumer.State.put(
      String.to_atom("queue#{guild_id}"),
      queue ++ [%{guild_id: guild_id, url: url}]
    )
  end

  defp dequeue(guild_id) do
    atom = String.to_atom("queue#{guild_id}")
    {first_of_queue, new_queue} = List.pop_at(AudioPlayerConsumer.State.get(atom), 0)
    AudioPlayerConsumer.State.put(atom, new_queue)
    first_of_queue
  end

  defp queue(guild_id) do
    String.to_atom("queue#{guild_id}") |> AudioPlayerConsumer.State.get()
  end

  defp parse_queue(guild_id) do
    queue = queue(guild_id) || []

    if Enum.count(queue) > 0 do
      queue
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} -> "#{item[:url]} - #{idx}" end)
      |> Enum.join("\n")
    else
      "queue is empty"
    end
  end

  defp create_guild_commands(guild_id) do
    Enum.each(@commands, fn {name, description, options} ->
      Api.create_guild_application_command(guild_id, %{
        name: name,
        description: description,
        options: options
      })
    end)
  end

  defp parse_option(interaction) do
    interaction |> List.first() |> Map.get(:options) |> List.first()
  end

  defp move_to_start(index, guild_id) do
    queue = queue(guild_id)
    index = String.to_integer(index)

    if(index < length(queue)) do
      item = Enum.at(queue, index, 0)
      [item | List.delete_at(queue, index)]
    else
      queue
    end
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
