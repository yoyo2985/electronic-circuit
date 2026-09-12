# voice_cap_rpt 端到端: 2帧已知特征 → 期望 M-line
quit -sim
vlib work
vlog ../../rtl/uart_tx.v ../../rtl/voice_cap_rpt.v ../tb_cap_rpt.v
vsim -c tb_cap_rpt
run -all
