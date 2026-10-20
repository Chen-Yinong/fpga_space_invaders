// centroid_calc.sv — 工业级防抖质心计算模块（双路并行时序安全除法器）
// 修复：消除 always 内局部变量声明，完全兼容 iverilog / Vivado 语法规范
`timescale 1ns/1ps

module centroid_calc #(
    parameter int MIN_PIX = 400     // 最小有效手部像素（调至 300~500，手远不丢，小杂点不触发）
)(
    input  logic              pclk,
    input  logic              rst_n,
    input  logic              pixel_en,
    input  logic              skin,
    input  logic              href,
    input  logic              vsync,
    
    output logic              valid,         // 本帧质心有效（画面有手）
    output logic [9:0]        cx,            // 平滑后的质心 X (0..639)
    output logic [8:0]        cy,            // 平滑后的质心 Y (0..479)
    output logic signed [10:0] dx            // 帧间位移速度 ΔX (正:向右挥, 负:向左挥)
);

    // =========================================================================
    // 1. 行列坐标计数与场沿检测
    // =========================================================================
    logic [11:0] pcnt, rcnt;
    logic href_d, vsync_d;

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pcnt    <= '0;
            rcnt    <= '0;
            href_d  <= 1'b0;
            vsync_d <= 1'b0;
        end else begin
            href_d  <= href;
            vsync_d <= vsync;
            if (vsync && !vsync_d) begin
                pcnt <= '0;
                rcnt <= '0;
            end else if (href && !href_d) begin
                pcnt <= '0;
                rcnt <= rcnt + 1'b1;
            end else if (pixel_en) begin
                pcnt <= pcnt + 1'b1;
            end
        end
    end

    wire frame_end = vsync && !vsync_d; // 帧画面扫描结束，进入场消隐

    // =========================================================================
    // 2. 像素流式累加
    // =========================================================================
    logic [27:0] xsum, ysum;
    logic [19:0] cnt;

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            xsum <= '0;
            ysum <= '0;
            cnt  <= '0;
        end else if (frame_end) begin
            xsum <= '0;
            ysum <= '0;
            cnt  <= '0;
        end else if (pixel_en && skin) begin
            xsum <= xsum + {16'b0, pcnt};
            ysum <= ysum + {16'b0, rcnt};
            cnt  <= cnt + 1'b1;
        end
    end

    // =========================================================================
    // 3. 双路并行 28 拍除法状态机（纯时序安全设计）
    // =========================================================================
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_DIV,
        ST_DONE
    } div_state_e;

    div_state_e div_st;
    logic [4:0]  div_step;     // 28 步计数
    logic [27:0] num_x, num_y; // 锁存的被除数
    logic [19:0] den;          // 锁存的除数 cnt
    logic [27:0] quo_x, quo_y; // 商
    logic [28:0] rem_x, rem_y; // 余数

    logic [9:0]  cx_raw;
    logic [8:0]  cy_raw;
    logic [9:0]  cx_prev;
    logic        has_prev;

    // 移到外部声明的组合逻辑连线，彻底解决 iverilog 语法报错
    wire [28:0] next_rem_x = {rem_x[27:0], num_x[27]};
    wire [28:0] next_rem_y = {rem_y[27:0], num_y[27]};

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            div_st    <= ST_IDLE;
            div_step  <= '0;
            num_x     <= '0;
            num_y     <= '0;
            den       <= '0;
            rem_x     <= '0;
            rem_y     <= '0;
            quo_x     <= '0;
            quo_y     <= '0;
            cx_raw    <= 10'd320;
            cy_raw    <= 9'd240;
            cx        <= 10'd320;
            cy        <= 9'd240;
            cx_prev   <= 10'd320;
            has_prev  <= 1'b0;
            dx        <= 11'sd0;
            valid     <= 1'b0;
        end else begin
            case (div_st)
                ST_IDLE: begin
                    if (frame_end) begin
                        if (cnt >= MIN_PIX) begin
                            div_st   <= ST_DIV;
                            div_step <= 5'd28;
                            num_x    <= xsum;
                            num_y    <= ysum;
                            den      <= cnt;
                            rem_x    <= '0;
                            rem_y    <= '0;
                            quo_x    <= '0;
                            quo_y    <= '0;
                        end else begin
                            valid    <= 1'b0;
                            has_prev <= 1'b0;
                            dx       <= 11'sd0;
                        end
                    end
                end

                // X 和 Y 在 28 拍内严格并行移位减法
                ST_DIV: begin
                    if (div_step > 5'd0) begin
                        div_step <= div_step - 1'b1;
                        num_x    <= {num_x[26:0], 1'b0};
                        num_y    <= {num_y[26:0], 1'b0};

                        // X 轴移位判断
                        if (next_rem_x >= {9'd0, den}) begin
                            rem_x <= next_rem_x - {9'd0, den};
                            quo_x <= {quo_x[26:0], 1'b1};
                        end else begin
                            rem_x <= next_rem_x;
                            quo_x <= {quo_x[26:0], 1'b0};
                        end

                        // Y 轴移位判断
                        if (next_rem_y >= {9'd0, den}) begin
                            rem_y <= next_rem_y - {9'd0, den};
                            quo_y <= {quo_y[26:0], 1'b1};
                        end else begin
                            rem_y <= next_rem_y;
                            quo_y <= {quo_y[26:0], 1'b0};
                        end
                    end else begin
                        cx_raw <= quo_x[9:0];
                        cy_raw <= quo_y[8:0];
                        div_st <= ST_DONE;
                    end
                end

                // 平滑滤波与挥手位移结算
                ST_DONE: begin
                    if (!has_prev) begin
                        cx       <= cx_raw;
                        cy       <= cy_raw;
                        cx_prev  <= cx_raw;
                        dx       <= 11'sd0;
                        has_prev <= 1'b1;
                    end else begin
                        // 50% 响应式平滑滤波
                        cx <= (cx >> 1) + (cx_raw >> 1);
                        cy <= (cy >> 1) + (cy_raw >> 1);

                        // 挥手位移差分 ΔX
                        dx      <= $signed({1'b0, cx_raw}) - $signed({1'b0, cx_prev});
                        cx_prev <= cx_raw;
                    end
                    valid  <= 1'b1;
                    div_st <= ST_IDLE;
                end
            endcase
        end
    end

endmodule