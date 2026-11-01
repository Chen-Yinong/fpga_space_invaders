// dir_judge_acc.sv —— dir_judge 的慢速积分增强版（cam_dual 专用）
//
// 原版问题：进入移动只看单帧 |dx| > TH_FAST(9px)，慢速挥手（1~8px/帧）
// 永远进不了门，飞机纹丝不动。
//
// 本版加一个带泄漏的累积器 acc：
//   acc_next = acc - (acc >>> ACC_SH) + dx    （每帧衰减 1/8 再累加）
// - 静止抖动是零均值 → 不积累，acc 稳在 ±几像素，不误触发
// - 慢速漂移同号 → 会积累，|acc| 越过 TH_ACC 就当一次有效移动触发，
//   并消耗掉 TH_ACC 的"额度"，之后重新积累 → 慢手 = 飞机脉冲式慢爬
//
// 速度档位（30fps 相机，全分辨率 640 宽坐标）：
//   |dx| >  9      → 立即移动，连续（原行为不变，acc 清零不参与）
//   |dx| = 4 ~ 9   → 短暂积累（约 3~6 帧）后连续移动
//   |dx| = 2 ~ 4   → 脉冲式爬行（移动 3 帧 + 积累若干帧循环）
//   |dx| < 2       → 静止（抖动保护；±3px 抖动的 acc 稳态 std≈3.5，距 16 有 4.6σ）
//
// 调参：误触发（手停着飞机自己动）→ TH_ACC 调大；
//       还是嫌钝 → ACC_SH 调大（泄漏更慢，增益更高，但抖动也更易积累）。
`timescale 1ns/1ps
module dir_judge_acc #(
  parameter signed [10:0] TH_FAST = 11'sd9,    // 进入移动的单帧门槛（像素/帧）
  parameter signed [10:0] TH_SLOW = 11'sd4,    // 维持移动的单帧底线
  parameter [2:0]         HOLD_MAX = 3'd3,     // 连续静止帧数后回停
  parameter signed [13:0] TH_ACC  = 14'sd16,   // 累积触发门限（像素·帧）
  parameter int           ACC_SH  = 3          // 泄漏移位（每帧衰减 1/2^ACC_SH）
)(
  input  logic               pclk,
  input  logic               rst_n,
  input  logic               frame_tick,    // 每帧一个脉冲（vsync 上升沿）
  input  logic               valid,         // 本帧有手
  input  logic signed [10:0] dx,            // 帧间位移（正=右，负=左）
  output logic               move_left,
  output logic               move_right
);
  typedef enum logic [1:0] { S_IDLE, S_LEFT, S_RIGHT } state_e;
  state_e state;
  logic [2:0] stop_cnt;

  // ---- 泄漏积分器 ----
  logic signed [13:0] acc;
  wire signed [13:0] dx14  = {{3{dx[10]}}, dx};      // 11 位符号扩展到 14 位
  wire signed [13:0] leak  = acc >>> ACC_SH;         // 每帧衰减 acc/8
  wire               fast  = (dx < -TH_FAST) || (dx > TH_FAST);
  wire               trig_l = (dx < -TH_FAST) || (acc <= -TH_ACC);
  wire               trig_r = (dx >  TH_FAST) || (acc >=  TH_ACC);

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n)        acc <= 14'sd0;
    else if (frame_tick) begin
      if (!valid)      acc <= 14'sd0;                                   // 没手：清零
      else if (fast)   acc <= 14'sd0;                                   // 快速位移直通
      else if (trig_l) acc <= acc - leak + dx14 + TH_ACC;               // 左触发：消耗额度
      else if (trig_r) acc <= acc - leak + dx14 - TH_ACC;               // 右触发：消耗额度
      else             acc <= acc - leak + dx14;                        // 平时：泄漏 + 累积
    end
  end

  // ---- 状态机（与 dir_judge 相同，进入/换向条件多了 acc 触发）----
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; stop_cnt <= '0;
    end else if (frame_tick) begin
      if (!valid) begin
        state <= S_IDLE; stop_cnt <= '0;
      end else begin
        case (state)
          S_IDLE: begin
            stop_cnt <= '0;
            if (trig_l)      state <= S_LEFT;
            else if (trig_r) state <= S_RIGHT;
          end
          S_LEFT: begin
            if (dx < -TH_SLOW)      stop_cnt <= '0;
            else if (trig_r)  begin state <= S_RIGHT; stop_cnt <= '0; end
            else if (stop_cnt >= HOLD_MAX) begin state <= S_IDLE; stop_cnt <= '0; end
            else                    stop_cnt <= stop_cnt + 1'b1;
          end
          S_RIGHT: begin
            if (dx > TH_SLOW)       stop_cnt <= '0;
            else if (trig_l)  begin state <= S_LEFT; stop_cnt <= '0; end
            else if (stop_cnt >= HOLD_MAX) begin state <= S_IDLE; stop_cnt <= '0; end
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
