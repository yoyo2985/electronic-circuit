# 帧控制器→feature_engine 连续出帧验证（在本目录 sim/audio_sim 执行）
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog ../../rtl/pre_emph.v ../../rtl/front_wind.v ../../rtl/front_chain.v \
     ../../rtl/fft_core.v ../../rtl/mel_bank.v ../../rtl/log2_lut.v \
     ../../rtl/logmel_chain.v ../../rtl/dct2_mfcc.v ../../rtl/feature_engine.v \
     ../../rtl/v2_frame_ctrl.v ../tb_v2_frame_ctrl.v
onerror {quit -f}
vsim work.tb_v2_frame_ctrl
run -all
quit -f
