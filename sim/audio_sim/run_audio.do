# A1 音频模块仿真一键运行（在本目录执行 do run_audio.do）
#   ModelSim GUI 打开后 cd sim/audio_sim，转录窗口输入:  do run_audio.do
#   依次跑 audio_pcm_bridge / audio_energy / audio_rpt 三个 TB，均期望 TEST PASS
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog ../../rtl/clock_enable.v ../../rtl/uart_tx.v ../../rtl/uart_rx.v \
     ../../rtl/audio_pcm_bridge.v ../../rtl/audio_energy.v ../../rtl/audio_rpt.v \
     ../tb_audio_pcm_bridge.v ../tb_audio_energy.v ../tb_audio_rpt.v

echo "======== 1/3 audio_pcm_bridge ========"
vsim work.tb_audio_pcm_bridge
run -all
quit -sim
echo "======== 2/3 audio_energy ============"
vsim work.tb_audio_energy
run -all
quit -sim
echo "======== 3/3 audio_rpt ==============="
vsim work.tb_audio_rpt
run -all
quit -sim
