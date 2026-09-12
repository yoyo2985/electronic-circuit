# 集成回归: top_voice_robot (V1 运动 + ES8388 + 语音链) —— 在本目录 sim/audio_sim 执行
#   引擎系数表 $readmemh "data/*.mem" 需 cwd=sim/audio_sim；模板 ../../data/... 亦从此解析。
#   VOICE_EN 默认 0 → 键盘/测试路径，运动回归应与 V1 一致；语音链例化但空闲。
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog ../../rtl/clock_enable.v ../../rtl/keypad_scan.v ../../rtl/target_input.v \
     ../../rtl/state_machine.v ../../rtl/virtual_motor.v ../../rtl/trajectory_planner.v \
     ../../rtl/pid_controller.v ../../rtl/fault_detector.v ../../rtl/seven_seg.v \
     ../../rtl/beep_gen.v ../../rtl/uart_tx.v ../../rtl/uart_telemetry.v \
     ../../rtl/pre_emph.v ../../rtl/front_wind.v ../../rtl/front_chain.v ../../rtl/fft_core.v fft_ram_64x32_sim.v \
     ../../rtl/mel_bank.v ../../rtl/log2_lut.v ../../rtl/logmel_chain.v ../../rtl/dct2_mfcc.v \
     ../../rtl/feature_engine.v ../../rtl/v2_frame_ctrl.v \
     ../../rtl/vtmpl.v ../../rtl/speaker_verify.v ../../rtl/utter_vote.v \
     ../../rtl/cmd_matcher.v ../../rtl/cmd_vote.v ../../rtl/decision_fsm.v ../../rtl/seg_decide.v ../../rtl/dir_energy.v \
     ../../rtl/voice_cap_rpt.v ../../rtl/voice_dbg_rpt.v \
     ../../rtl/audio/es8388_config.v ../../rtl/audio/i2c_dri.v ../../rtl/audio/i2c_reg_cfg.v \
     _sim_clk_wiz_0.v ../../rtl/audio_pcm_bridge.v ../../rtl/audio_energy.v \
     ../../rtl/audio_vad.v ../../rtl/audio_calib_rpt.v \
     ../../rtl/top_voice_robot.v ../../rtl/top_system.v ../tb_top_voice_robot.v ../tb_voice_dbg.v
onerror {quit -f}
vsim work.tb_top_voice_robot
run -all
vsim work.tb_voice_dbg
run -all
quit -f
