# utter_vote 段级累计回归 —— 在本目录 sim/audio_sim 执行
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog ../../rtl/utter_vote.v ../tb_utter_vote.v
onerror {quit -f}
vsim work.tb_utter_vote
run -all
quit -f
