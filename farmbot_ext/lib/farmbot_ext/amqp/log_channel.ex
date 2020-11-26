defmodule FarmbotExt.AMQP.LogChannel do
  @moduledoc """
  Handler for AMQP log channel
  """

  use AMQP
  use GenServer

  require FarmbotCore.Logger
  require FarmbotTelemetry
  require Logger

  alias FarmbotCore.{BotState, JSON}
  alias FarmbotExt.AMQP.Support

  @checkup_ms 150
  @exchange "amq.topic"

  defstruct [:conn, :chan, :jwt, :state_cache]
  alias __MODULE__, as: State

  @doc false
  def start_link(args, opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def init(args) do
    jwt = Keyword.fetch!(args, :jwt)
    {:ok, %State{conn: nil, chan: nil, jwt: jwt, state_cache: nil}, 0}
  end

  def terminate(r, s), do: Support.handle_termination(r, s, "Log")

  def handle_info({BotState, change}, state) do
    new_state_cache = Ecto.Changeset.apply_changes(change)
    {:noreply, %{state | state_cache: new_state_cache}, wait()}
  end

  # (inital state) Perform polling until we have a cached
  # version of bot state handy.
  # Cached bot state is used to attach X/Y/Z data to logs.
  def handle_info(:timeout, %{state_cache: nil} = state) do
    with {:ok, {conn, chan}} <- Support.create_channel() do
      initial_bot_state = BotState.subscribe()

      FarmbotExt.Time.no_reply(
        %{state | conn: conn, chan: chan, state_cache: initial_bot_state},
        0
      )
    else
      nil ->
        FarmbotExt.Time.no_reply(%{state | conn: nil, chan: nil, state_cache: nil}, 5000)

      err ->
        Support.connect_fail("Log", err)
        FarmbotExt.Time.no_reply(%{state | conn: nil, chan: nil, state_cache: nil}, 1000)
    end
  end

  # Perform regular polling every @checkup_ms after bot state
  # is cached.
  def handle_info(:timeout, state) do
    FarmbotCore.Logger.handle_all_logs()
    |> Enum.map(fn log ->
      case do_handle_log(log, state) do
        :ok ->
          Logger.debug("========== OK LOG :) #{log.message}")
          {log, :ok}

        error ->
          Logger.error("Logger amqp client failed to upload log: #{inspect(error)}")
          # Reschedule log to be uploaded again
          FarmbotCore.Logger.insert_log!(log)
          Logger.debug("========== ERROR LOG :( #{log.message}")
          {log, error}
      end
    end)

    {:noreply, state, wait()}
  end

  defp do_handle_log(log, state) do
    if FarmbotCore.Logger.should_log?(log.module, log.verbosity) do
      fb = %{position: %{x: nil, y: nil, z: nil}}
      location_data = Map.get(state.state_cache || %{}, :location_data, fb)

      log_without_pos = %{
        type: log.level,
        x: nil,
        y: nil,
        z: nil,
        verbosity: log.verbosity,
        major_version: log.version.major,
        minor_version: log.version.minor,
        patch_version: log.version.patch,
        # QUESTION(Connor) - Why does this need `.to_unix()`?
        # ANSWER(Connor) - because the FE needed it.
        created_at: DateTime.from_naive!(log.inserted_at, "Etc/UTC") |> DateTime.to_unix(),
        channels: log.meta[:channels] || log.meta["channels"] || [],
        meta: %{
          assertion_passed: log.meta[:assertion_passed],
          assertion_type: log.meta[:assertion_type]
        },
        message: log.message
      }

      json_log = add_position_to_log(log_without_pos, location_data)
      push_bot_log(state.chan, state.jwt.bot, json_log)
    else
      :ok
    end
  end

  defp push_bot_log(chan, bot, log) do
    # this will add quite a bit of overhead to logging, but probably not
    # that big of a deal.
    # List extracted from:
    # https://github.com/FarmBot/Farmbot-Web-App/blob/b7f09e51e856bfca5cfedd7fef3c572bebdbe809/frontend/devices/actions.ts#L38
    if Regex.match?(~r(WPA|PSK|PASSWORD|NERVES), String.upcase(log.message)) do
      :ok
    else
      json = JSON.encode!(log, pretty: true)
      :ok = Basic.publish(chan, @exchange, "bot.#{bot}.logs", json)
    end
  end

  defp add_position_to_log(%{} = log, %{position: %{x: x, y: y, z: z}}) do
    Map.merge(log, %{x: x, y: y, z: z})
  end

  defp wait() do
    if FarmbotCore.Project.env() == :test do
      1
    else
      @checkup_ms
    end
  end
end
