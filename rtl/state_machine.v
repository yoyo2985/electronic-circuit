//------------------------------------------------------------------------------
// state_machine.v   运行状态机（12）
//   状态：IDLE → READY → MOVE → HOLD，任意态收到故障进 FAULT，ACK 才回 IDLE。
//     IDLE : 空闲。target_valid 后进 READY(已设定目标未启动)；若 start 同来则直进 MOVE。
//     READY: 就绪。start → MOVE；fault_in → FAULT。
//     MOVE : 运动中。at_target → HOLD；fault_in → FAULT。
//     HOLD : 到位保持。start(新目标)&&target_valid → MOVE；fault_in → FAULT。
//     FAULT: 故障锁定。ack → IDLE。
// 输入电平一拍有效即可(建议外部给脉冲)。
// 复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module state_machine (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       target_valid,   // 已有确认目标
    input  wire       start,          // 启动/重新启动
    input  wire       at_target,      // 已到位
    input  wire       fault_in,       // 故障(堵转/越界等)
    input  wire       ack,            // 故障确认清除
    output reg  [2:0] state,
    output wire       moving,         // 1=运动中
    output wire       faulted         // 1=故障态
);
    localparam S_IDLE  = 3'd0;
    localparam S_READY = 3'd1;
    localparam S_MOVE  = 3'd2;
    localparam S_HOLD  = 3'd3;
    localparam S_FAULT = 3'd4;

    always @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else begin
            case (state)
                S_IDLE:  if (fault_in) state <= S_FAULT;
                         else if (target_valid && start) state <= S_MOVE;
                         else if (target_valid)          state <= S_READY;
                S_READY: if (fault_in)      state <= S_FAULT;
                         else if (start)    state <= S_MOVE;
                S_MOVE:  if (fault_in)      state <= S_FAULT;
                         else if (at_target) state <= S_HOLD;
                S_HOLD:  if (fault_in)                           state <= S_FAULT;
                         else if (start && target_valid)         state <= S_MOVE;
                S_FAULT: if (ack) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    assign moving  = (state == S_MOVE);
    assign faulted = (state == S_FAULT);
endmodule
