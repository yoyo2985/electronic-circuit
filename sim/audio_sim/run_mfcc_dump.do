# 真实录音 PCM → feature_engine → 逐系数转储(在本目录 sim/audio_sim 执行)
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog ../../rtl/pre_emph.v ../../rtl/front_wind.v ../../rtl/front_chain.v \
     ../../rtl/fft_core.v ../../rtl/mel_bank.v ../../rtl/log2_lut.v \
     ../../rtl/logmel_chain.v ../../rtl/dct2_mfcc.v ../../rtl/feature_engine.v \
     fft_ram_64x32_sim.v ../tb_mfcc_dump.v
onerror {quit -f}
vsim -c work.tb_mfcc_dump
run -all
quit -f
