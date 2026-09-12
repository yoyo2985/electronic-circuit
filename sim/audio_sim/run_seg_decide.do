quit -sim
vlib work
vlog ../../rtl/seg_decide.v ../tb_seg_decide.v
vsim -c tb_seg_decide
run -all
