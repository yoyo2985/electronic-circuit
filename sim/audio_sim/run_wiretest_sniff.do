# I2S 嗅探固件仿真：vsim -c -do run_wiretest_sniff.do （在 sim/audio_sim 下执行）
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog ../../rtl/top_audio_wiretest.v \
     _sim_clk_wiz_0.v \
     ../../rtl/audio/es8388_config.v \
     ../../rtl/audio/i2c_reg_cfg.v \
     ../../rtl/audio/i2c_dri.v \
     ../../rtl/clock_enable.v \
     ../../rtl/sig_activity.v \
     ../../rtl/audio_pcm_bridge.v \
     ../../rtl/uart_tx.v \
     ../tb_top_audio_wiretest.v
onerror {quit -f}
vsim work.tb_top_audio_wiretest
run 150ms
quit -f
