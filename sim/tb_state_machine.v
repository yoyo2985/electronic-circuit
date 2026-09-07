`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_state_machine.v
//   依次验证：IDLE→READY→MOVE→HOLD→FAULT→ACK→IDLE；以及 IDLE 同时 start 直进 MOVE。
//------------------------------------------------------------------------------
module tb_state_machine;
    reg clk = 0;
    reg rst_n = 0;
    reg target_valid = 0, start = 0, at_target = 0, fault_in = 0, ack = 0;
    wire [2:0] state;
    wire moving, faulted;

    state_machine dut (
        .clk(clk), .rst_n(rst_n), .target_valid(target_valid), .start(start),
        .at_target(at_target), .fault_in(fault_in), .ack(ack),
        .state(state), .moving(moving), .faulted(faulted)
    );

    always #10 clk = ~clk;

    task automatic pulse(input [4:0] sel);   // bit0 tvalid 1 start 2 att 3 fault 4 ack
        begin
            @(posedge clk);
            target_valid = sel[0]; start = sel[1]; at_target = sel[2];
            fault_in = sel[3]; ack = sel[4];
            @(posedge clk);
            target_valid = 0; start = 0; at_target = 0; fault_in = 0; ack = 0;
            repeat (2) @(posedge clk);
        end
    endtask

    integer err;
    initial begin
        err = 0;
        $display("=== tb_state_machine start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (3) @(posedge clk);

        if (state == 3'd0) $display("PASS IDLE");
        else begin $display("FAIL 初态=%0d", state); err = err + 1; end

        pulse(5'b00001);        // target_valid
        if (state == 3'd1) $display("PASS READY");
        else begin $display("FAIL READY=%0d", state); err = err + 1; end

        pulse(5'b00010);        // start
        if (state == 3'd2 && moving) $display("PASS MOVE");
        else begin $display("FAIL MOVE=%0d", state); err = err + 1; end

        pulse(5'b00100);        // at_target
        if (state == 3'd3) $display("PASS HOLD");
        else begin $display("FAIL HOLD=%0d", state); err = err + 1; end

        pulse(5'b01000);        // fault
        if (state == 3'd4 && faulted) $display("PASS FAULT");
        else begin $display("FAIL FAULT=%0d", state); err = err + 1; end

        pulse(5'b10000);        // ack
        if (state == 3'd0) $display("PASS ACK→IDLE");
        else begin $display("FAIL ACK=%0d", state); err = err + 1; end

        pulse(5'b00011);        // target_valid+start 同时 -> MOVE
        if (state == 3'd2) $display("PASS 直接启动→MOVE");
        else begin $display("FAIL 直启=%0d", state); err = err + 1; end

        if (err == 0) $display("=== tb_state_machine PASS ===");
        else          $display("=== tb_state_machine FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
