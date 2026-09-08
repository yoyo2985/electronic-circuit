//------------------------------------------------------------------------------
// tb_front_wind.v   B3-2 分帧+加窗 Golden 比对
//   向量 data/hann_64.mem + front_in.mem + front_exp.mem 由 py/gen_wind_vec.py 生成。
//   N=64, 3 帧。采样按 SP=200 拍间隔喂入（>64 拍读帧，不会与写入重叠）。
//   逐点比对加窗输出 → 全 PASS。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_front_wind;

    localparam AW = 24;
    localparam N = 64;
    localparam FRAMES = 3;
    localparam TOTAL = FRAMES * N;
    localparam SP = 200;

    reg clk = 1'b0, rst_n = 1'b0;
    reg sample_ok = 1'b0;
    reg signed [AW-1:0] sample = 0;
    wire out_valid, out_first;
    wire signed [AW-1:0] out_data;

    front_wind #(.AW(AW), .N(N)) DUT (
        .clk(clk), .rst_n(rst_n), .sample_ok(sample_ok), .sample(sample),
        .out_valid(out_valid), .out_first(out_first), .out_data(out_data)
    );

    always #10 clk = ~clk;

    reg [AW-1:0] xin[0:TOTAL-1];
    reg [AW-1:0] exp[0:TOTAL-1];

    integer i, oc, fc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < TOTAL && out_data !== exp[oc]) begin
                if (err < 8)
                    $display("[ERR] idx %0d out=%06h exp=%06h", oc, out_data, exp[oc]);
                err = err + 1;
            end
            oc = oc + 1;
        end
        if (out_first) fc = fc + 1;
    end

    initial begin
        $readmemh("data/front_in.mem", xin);
        $readmemh("data/front_exp.mem", exp);

        oc = 0; fc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < TOTAL; i = i + 1) begin
            sample     = $signed(xin[i]);
            sample_ok  = 1'b1;
            @(posedge clk);
            sample_ok  = 1'b0;
            repeat(SP - 1) @(posedge clk);   // 真实 48k 采样间隔远大于读帧
        end
        repeat(N + 5) @(posedge clk);         // 等最后一帧读帧完成

        if (oc != TOTAL) begin
            $display("[ERR] out count %0d want %0d", oc, TOTAL);
            err = err + 1;
        end
        if (fc != FRAMES) begin
            $display("[ERR] frame count %0d want %0d", fc, FRAMES);
            err = err + 1;
        end
        if (err == 0)
            $display("TEST PASS : %0d windowed samples, %0d frames, bit-exact", oc, fc);
        else
            $display("TEST FAIL : oc=%0d fc=%0d err=%0d", oc, fc, err);
        $finish;
    end

    initial #2000000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
