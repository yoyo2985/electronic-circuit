quit -sim
vlib work
vlog ../../rtl/dir_energy.v ../tb_dir_energy.v
vsim -c tb_dir_energy
run -all
