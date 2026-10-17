// gesture_dir_fsm.sv
// 握拳手势方向决策：根据「拇指尖 - 掌心」水平偏移 dx 判定左移/右移。
// 输入 dx 由视觉流水线提供（vision_pipeline -> 最远点找拇指尖 -> dx），
// 本模块只做：迟滞 + 去抖 + 命令编码。
//
// 与 docs/gesture_spec.md 的命令语义一致：
//   cmd[0]=1 左移(电平)  cmd[1]=1 右移(电平)  cmd=0 无命令
// 作者: C(游戏/集成), 日期: 2026-10-11

module gesture_dir_fsm #(
  parameter int ENTER_TH = 25,   // dx 进入阈值（像素），|dx| > ENTER_TH 才判左/右
  parameter int EXIT_TH  = 15,   // dx 退出阈值（迟滞），|dx| < EXIT_TH 才回 idle
  parameter int MIN_DIST = 50,   // 拇指尖到掌心最小距离，小于它视为未伸拇指
  parameter int N_ON  = 5,       // 进入去抖帧数
  parameter int N_OFF = 3        // 退出去抖帧数
)(
  input  logic              clk_sys,     // 100 MHz 主时钟
  input  logic              rst_n,       // 低有效异步复位
  input  logic              frame_tick,  // 每帧一个 clk 周期的脉冲
  input  logic              feat_valid,  // 本帧有有效手部
  input  logic signed [11:0] dx,         // tip.x - palm.x，有符号
  input  logic        [9:0] tip_dist,     // tip 到 palm 距离（像素）
  output logic              cmd_valid,
  output logic        [3:0] cmd          // 0001 左移, 0010 右移
);
  localparam logic [3:0] CMD_LEFT  = 4'b0001;
  localparam logic [3:0] CMD_RIGHT = 4'b0010;

  typedef enum logic [1:0] { S_IDLE, S_LEFT, S_RIGHT } state_t;
  state_t state;
  localparam int MAXC = (N_ON > N_OFF) ? N_ON : N_OFF;
  logic [$clog2(MAXC+1)-1:0] cnt;

  always_ff @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      cnt   <= '0;
    end else if (frame_tick) begin
      if (!feat_valid || tip_dist < MIN_DIST) begin
        // 无效帧：保持当前命令（手短暂丢失不停机）
        cnt <= '0;
      end else begin
        unique case (state)
          S_IDLE: begin
            if (dx < -ENTER_TH) begin
              if (cnt >= N_ON-1) begin state <= S_LEFT;  cnt <= '0; end
              else               begin cnt <= cnt + 1'b1; end
            end else if (dx > ENTER_TH) begin
              if (cnt >= N_ON-1) begin state <= S_RIGHT; cnt <= '0; end
              else               begin cnt <= cnt + 1'b1; end
            end else begin
              cnt <= '0;
            end
          end
          S_LEFT: begin
            if (dx > -EXIT_TH) begin               // 离开左区（进入死区或右侧）
              if (cnt >= N_OFF-1) begin state <= S_IDLE; cnt <= '0; end
              else                begin cnt <= cnt + 1'b1; end
            end else begin
              cnt <= '0;
            end
          end
          S_RIGHT: begin
            if (dx < EXIT_TH) begin                 // 离开右区
              if (cnt >= N_OFF-1) begin state <= S_IDLE; cnt <= '0; end
              else                begin cnt <= cnt + 1'b1; end
            end else begin
              cnt <= '0;
            end
          end
          default: state <= S_IDLE;
        endcase
      end
    end
  end

  always_comb begin
    unique case (state)
      S_LEFT:  begin cmd_valid = 1'b1; cmd = CMD_LEFT;  end
      S_RIGHT: begin cmd_valid = 1'b1; cmd = CMD_RIGHT; end
      default: begin cmd_valid = 1'b0; cmd = 4'b0000;   end
    endcase
  end
endmodule