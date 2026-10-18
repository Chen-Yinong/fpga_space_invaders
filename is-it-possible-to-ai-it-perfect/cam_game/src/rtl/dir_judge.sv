// dir_judge.sv — 手势方向判定（施密特迟滞 + 退出去抖）
// 输入 centroid_calc 的帧间位移 dx（正=右，负=左），输出左右移动电平。
`timescale 1ns/1ps
module dir_judge #(
  parameter signed [10:0] TH_FAST = 11'sd9,   // 进入移动的门槛（像素/帧）
  parameter signed [10:0] TH_SLOW = 11'sd4,   // 维持移动的底线
  parameter [2:0]         HOLD_MAX = 3'd3     // 连续静止帧数后回停
)(
  input  logic              pclk,
  input  logic              rst_n,
  input  logic              frame_tick,   // 每帧一个脉冲
  input  logic              valid,        // 本帧有手
  input  logic signed [10:0] dx,
  output logic              move_left,
  output logic              move_right
);
  typedef enum logic [1:0] { S_IDLE, S_LEFT, S_RIGHT } state_e;
  state_e state;
  logic [2:0] stop_cnt;

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      state<=S_IDLE; stop_cnt<='0;
    end else if (frame_tick) begin
      if (!valid) begin
        state<=S_IDLE; stop_cnt<='0;
      end else begin
        case (state)
          S_IDLE: begin
            stop_cnt <= '0;
            if (dx < -TH_FAST)      state <= S_LEFT;
            else if (dx > TH_FAST)  state <= S_RIGHT;
          end
          S_LEFT: begin
            if (dx < -TH_SLOW)      stop_cnt <= '0;
            else if (dx > TH_FAST)  begin state<=S_RIGHT; stop_cnt<='0; end
            else if (stop_cnt >= HOLD_MAX) begin state<=S_IDLE; stop_cnt<='0; end
            else                    stop_cnt <= stop_cnt + 1'b1;
          end
          S_RIGHT: begin
            if (dx > TH_SLOW)       stop_cnt <= '0;
            else if (dx < -TH_FAST) begin state<=S_LEFT; stop_cnt<='0; end
            else if (stop_cnt >= HOLD_MAX) begin state<=S_IDLE; stop_cnt<='0; end
            else                    stop_cnt <= stop_cnt + 1'b1;
          end
          default: state <= S_IDLE;
        endcase
      end
    end
  end

  assign move_left  = (state == S_LEFT);
  assign move_right = (state == S_RIGHT);
endmodule
