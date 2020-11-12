defmodule FarmbotCore.FirmwareSideEffects do
  @moduledoc "Handles firmware data and syncing it with BotState."
  @behaviour FarmbotFirmware.SideEffects
  require Logger
  require FarmbotCore.Logger
  alias FarmbotCore.{Asset, BotState, FirmwareEstopTimer, Leds}

  @impl FarmbotFirmware.SideEffects
  def handle_position(x: x, y: y, z: z) do
    :ok = BotState.set_position(x, y, z)
  end

  @impl FarmbotFirmware.SideEffects
  def handle_load([_u, x, _v, y, _w, z]) do
    :ok = BotState.set_load(x, y, z)
  end

  @impl FarmbotFirmware.SideEffects
  def handle_position_change([{axis, 0.0}]) do
    FarmbotCore.Logger.warn(1, "#{axis}-axis stopped at home")
    :noop
  end

    @impl FarmbotFirmware.SideEffects
  def handle_position_change([{axis, _}]) do
    FarmbotCore.Logger.warn(1, "#{axis}-axis stopped at maximum")
    :noop
  end

  @impl FarmbotFirmware.SideEffects
  def handle_axis_state([{axis, state}]) do
    BotState.set_axis_state(axis, state)
  end

  @impl FarmbotFirmware.SideEffects
  def handle_axis_timeout(axis) do
    FarmbotCore.Logger.error(1, "#{axis}-axis timed out waiting for movement to complete")
    :noop
  end

  @impl FarmbotFirmware.SideEffects
  def handle_home_complete(_) do
    :noop
  end

  @impl FarmbotFirmware.SideEffects
  def handle_calibration_state([{_axis, _state}]) do
    :noop
  end

  @impl FarmbotFirmware.SideEffects
  def handle_encoders_scaled(x: x, y: y, z: z) do
    :ok = BotState.set_encoders_scaled(x, y, z)
  end

  # this is a bug in the firmware code i think
  def handle_encoders_scaled([]), do: :noop

  @impl FarmbotFirmware.SideEffects
  def handle_encoders_raw(x: x, y: y, z: z) do
    :ok = BotState.set_encoders_raw(x, y, z)
  end

  @impl FarmbotFirmware.SideEffects
  def handle_parameter_value([{param, value}]) do
    :ok = BotState.set_firmware_config(param, value)
  end

  @impl FarmbotFirmware.SideEffects
  def handle_parameter_calibration_value([{_, 0}]), do: :ok
  def handle_parameter_calibration_value([{_, 0.0}]), do: :ok
  def handle_parameter_calibration_value([{param, value}]) do
    FarmbotCeleryScript.SysCalls.sync()
    Process.sleep(1000)
    %{param => value}
    |> Asset.update_firmware_config!()
    |> Asset.Private.mark_dirty!(%{})
    :ok
  end

  @impl FarmbotFirmware.SideEffects
  def handle_pin_value(p: pin, v: value) do
    :ok = BotState.set_pin_value(pin, value)
  end

  @impl FarmbotFirmware.SideEffects
  def handle_software_version([version]) do
    :ok = BotState.set_firmware_version(version)

    case String.split(version, ".") do
      # Ramps
      [_, _, _, "R"] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("arduino")
      [_, _, _, "R", _] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("arduino")

      # Farmduino
      [_, _, _, "F"] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("farmduino")
      [_, _, _, "F", _] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("farmduino")

      # Farmduino V14
      [_, _, _, "G"] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("farmduino_k14")
      [_, _, _, "G", _] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("farmduino_k14")

      # Farmduino V15
      [_, _, _, "H"] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("farmduino_k15")
      [_, _, _, "H", _] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("farmduino_k15")

      # Express V10
      [_, _, _, "E"] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("express_k10")
      [_, _, _, "E", _] ->
        _ = Leds.red(:solid)
        :ok = BotState.set_firmware_hardware("express_k10")

      [_, _, _, "S"] ->
        _ = Leds.red(:slow_blink)
        :ok = BotState.set_firmware_version("none")
        :ok = BotState.set_firmware_hardware("none")
      [_, _, _, "S", _] ->
        _ = Leds.red(:slow_blink)
        :ok = BotState.set_firmware_version("none")
        :ok = BotState.set_firmware_hardware("none")
    end
  end

  @impl FarmbotFirmware.SideEffects
  def handle_end_stops(_) do
    :noop
  end

  @impl FarmbotFirmware.SideEffects
  def handle_busy(busy) do
    :ok = BotState.set_firmware_busy(busy)
  end

  @impl FarmbotFirmware.SideEffects
  def handle_idle(idle) do
    _ = FirmwareEstopTimer.cancel_timer()
    :ok = BotState.set_firmware_unlocked()
    :ok = BotState.set_firmware_idle(idle)
  end

  @impl FarmbotFirmware.SideEffects
  def handle_emergency_lock() do
    _ = FirmwareEstopTimer.start_timer()
    _ = Leds.red(:fast_blink)
    _ = Leds.yellow(:slow_blink)
    :ok = BotState.set_firmware_locked()
  end

  @impl FarmbotFirmware.SideEffects
  def handle_emergency_unlock() do
    _ = FirmwareEstopTimer.cancel_timer()
    _ = Leds.red(:solid)
    _ = Leds.yellow(:off)
    :ok = BotState.set_firmware_unlocked()
  end

  @impl FarmbotFirmware.SideEffects

  def handle_input_gcode(_) do
    :ok
  end

  @impl FarmbotFirmware.SideEffects
  def handle_output_gcode(_code) do
    :ok
  end

  @impl FarmbotFirmware.SideEffects
  def handle_debug_message([_message]) do
    :ok
  end

  # TODO(Rick): 0 means OK, but firmware debug logs say "error 0". Why?
  def do_send_debug_message("error 0"), do: do_send_debug_message("OK")

  def do_send_debug_message(message) do
    FarmbotCore.Logger.debug(3, "Firmware debug message: " <> message)
  end

  @impl FarmbotFirmware.SideEffects
  def load_params do
    conf = Asset.firmware_config()
    known_params(conf)
  end

  def known_params(conf) do
    Map.take(conf, [
      :param_e_stop_on_mov_err,
      :param_mov_nr_retry,
      :movement_timeout_x,
      :movement_timeout_y,
      :movement_timeout_z,
      :movement_keep_active_x,
      :movement_keep_active_y,
      :movement_keep_active_z,
      :movement_home_at_boot_x,
      :movement_home_at_boot_y,
      :movement_home_at_boot_z,
      :movement_invert_endpoints_x,
      :movement_invert_endpoints_y,
      :movement_invert_endpoints_z,
      :movement_enable_endpoints_x,
      :movement_enable_endpoints_y,
      :movement_enable_endpoints_z,
      :movement_invert_motor_x,
      :movement_invert_motor_y,
      :movement_invert_motor_z,
      :movement_secondary_motor_x,
      :movement_secondary_motor_invert_x,
      :movement_steps_acc_dec_x,
      :movement_steps_acc_dec_y,
      :movement_steps_acc_dec_z,
      :movement_steps_acc_dec_z2,
      :movement_stop_at_home_x,
      :movement_stop_at_home_y,
      :movement_stop_at_home_z,
      :movement_home_up_x,
      :movement_home_up_y,
      :movement_home_up_z,
      :movement_step_per_mm_x,
      :movement_step_per_mm_y,
      :movement_step_per_mm_z,
      :movement_min_spd_x,
      :movement_min_spd_y,
      :movement_min_spd_z,
      :movement_min_spd_z2,
      :movement_home_spd_x,
      :movement_home_spd_y,
      :movement_home_spd_z,
      :movement_max_spd_x,
      :movement_max_spd_y,
      :movement_max_spd_z,
      :movement_max_spd_z2,
      :movement_invert_2_endpoints_x,
      :movement_invert_2_endpoints_y,
      :movement_invert_2_endpoints_z,
      :movement_motor_current_x,
      :movement_motor_current_y,
      :movement_motor_current_z,
      :movement_stall_sensitivity_x,
      :movement_stall_sensitivity_y,
      :movement_stall_sensitivity_z,
      :movement_microsteps_x,
      :movement_microsteps_y,
      :movement_microsteps_z,
      :encoder_enabled_x,
      :encoder_enabled_y,
      :encoder_enabled_z,
      :encoder_type_x,
      :encoder_type_y,
      :encoder_type_z,
      :encoder_missed_steps_max_x,
      :encoder_missed_steps_max_y,
      :encoder_missed_steps_max_z,
      :encoder_scaling_x,
      :encoder_scaling_y,
      :encoder_scaling_z,
      :encoder_missed_steps_decay_x,
      :encoder_missed_steps_decay_y,
      :encoder_missed_steps_decay_z,
      :encoder_use_for_pos_x,
      :encoder_use_for_pos_y,
      :encoder_use_for_pos_z,
      :encoder_invert_x,
      :encoder_invert_y,
      :encoder_invert_z,
      :movement_axis_nr_steps_x,
      :movement_axis_nr_steps_y,
      :movement_axis_nr_steps_z,
      :movement_stop_at_max_x,
      :movement_stop_at_max_y,
      :movement_stop_at_max_z,
      :pin_guard_1_pin_nr,
      :pin_guard_1_time_out,
      :pin_guard_1_active_state,
      :pin_guard_2_pin_nr,
      :pin_guard_2_time_out,
      :pin_guard_2_active_state,
      :pin_guard_3_pin_nr,
      :pin_guard_3_time_out,
      :pin_guard_3_active_state,
      :pin_guard_4_pin_nr,
      :pin_guard_4_time_out,
      :pin_guard_4_active_state,
      :pin_guard_5_pin_nr,
      :pin_guard_5_time_out,
      :pin_guard_5_active_state
    ])
  end
end
