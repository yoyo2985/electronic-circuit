vlib work
vlog ../rtl/clock_enable.v ../rtl/led_ctrl.v ../rtl/seven_seg.v ../rtl/top_blink.v ../rtl/top_seg.v ../rtl/switch_input.v ../rtl/top_sw.v ../rtl/keypad_scan.v ../rtl/top_key.v ../rtl/uart_tx.v ../rtl/top_uart_tx.v ../rtl/uart_rx.v ../rtl/top_uart_loop.v ../rtl/target_input.v ../rtl/top_target.v ../rtl/beep_gen.v ../rtl/virtual_motor.v ../rtl/top_motor.v ../rtl/pid_controller.v ../rtl/top_pid.v ../rtl/trajectory_planner.v ../rtl/state_machine.v ../rtl/fault_detector.v ../rtl/uart_telemetry.v ../rtl/top_system.v
vlog tb_clock_enable.v tb_led_ctrl.v tb_seven_seg.v tb_top_blink.v tb_top_seg.v tb_switch_input.v tb_keypad_scan.v tb_top_key.v tb_uart_tx.v tb_top_uart_tx.v tb_uart_rx.v tb_top_uart_loop.v tb_target_input.v tb_top_target.v tb_beep_gen.v tb_virtual_motor.v tb_top_motor.v tb_pid_controller.v tb_top_pid.v tb_trajectory_planner.v tb_state_machine.v tb_fault_detector.v tb_uart_telemetry.v tb_top_system.v

vsim -c work.tb_clock_enable
run -all
quit -sim

vsim -c work.tb_led_ctrl
run -all
quit -sim

vsim -c work.tb_seven_seg
run -all
quit -sim

vsim -c work.tb_top_blink
run -all
quit -sim

vsim -c work.tb_top_seg
run -all
quit -sim

vsim -c work.tb_switch_input
run -all
quit -sim

vsim -c work.tb_keypad_scan
run -all
quit -sim

vsim -c work.tb_top_key
run -all
quit -sim

vsim -c work.tb_uart_tx
run -all
quit -sim

vsim -c work.tb_top_uart_tx
run -all
quit -sim

vsim -c work.tb_uart_rx
run -all
quit -sim

vsim -c work.tb_top_uart_loop
run -all
quit -sim

vsim -c work.tb_target_input
run -all
quit -sim

vsim -c work.tb_top_target
run -all
quit -sim

vsim -c work.tb_beep_gen
run -all
quit -sim

vsim -c work.tb_virtual_motor
run -all
quit -sim

vsim -c work.tb_top_motor
run -all
quit -sim

vsim -c work.tb_pid_controller
run -all
quit -sim

vsim -c work.tb_top_pid
run -all
quit -sim

vsim -c work.tb_trajectory_planner
run -all
quit -sim

vsim -c work.tb_state_machine
run -all
quit -sim

vsim -c work.tb_fault_detector
run -all
quit -sim

vsim -c work.tb_uart_telemetry
run -all
quit -sim

vsim -c work.tb_top_system
run -all
quit -sim
