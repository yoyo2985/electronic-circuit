if {[file exists work]} { vdel -all -lib work }
vlib work
vlog ../rtl/clock_enable.v ../rtl/keypad_scan.v ../rtl/target_input.v \
     ../rtl/state_machine.v ../rtl/virtual_motor.v ../rtl/trajectory_planner.v \
     ../rtl/pid_controller.v ../rtl/fault_detector.v ../rtl/seven_seg.v \
     ../rtl/beep_gen.v ../rtl/uart_tx.v ../rtl/uart_telemetry.v \
     ../rtl/audio/es8388_config.v ../rtl/audio/i2c_dri.v ../rtl/audio/i2c_reg_cfg.v \
     audio_sim/_sim_clk_wiz_0.v ../rtl/audio_pcm_bridge.v ../rtl/audio_energy.v \
     ../rtl/audio_vad.v ../rtl/audio_calib_rpt.v ../rtl/top_voice_robot.v \
     tb_calib_smoke.v
vsim -c work.tb_calib_smoke
run -all
quit -sim
