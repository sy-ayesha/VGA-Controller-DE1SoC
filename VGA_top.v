module VGA_top (
    input  wire CLOCK_50,      // DE1-SoC onboard 50MHz clock
    input  wire [3:0] KEY,     // Push buttons (KEY[0] hum reset ke liye use karenge)
    output wire VGA_HS,        // Horizontal Sync
    output wire VGA_VS,        // Vertical Sync
    output wire [7:0] VGA_R,   // Red (8-bit, DE1-SoC VGA DAC ke hisab se)
    output wire [7:0] VGA_G,   // Green
    output wire [7:0] VGA_B,   // Blue
    output wire VGA_CLK,       // Pixel clock output to VGA port
    output wire VGA_BLANK_N,   // Blanking signal
    output wire VGA_SYNC_N,    // Composite sync (usually tied to 1'b0)
    output wire [9:0] LEDR     // Red LEDs (PLL lock indicator ke liye)
);

    wire clk_65mhz;
    wire pll_locked;
    wire reset_n;

    assign reset_n = KEY[0];   // KEY0 dabane se reset hoga (active-low button)

    // ============================================
    // PLL Instantiation
    // ============================================
    pll65m_0002 u_pll (
        .refclk  (CLOCK_50),
        .rst     (~reset_n),      // rst active-high hai, isliye KEY ko invert kiya
        .outclk_0(clk_65mhz),
        .locked  (pll_locked)
    );

    // PLL lock status LED pe dikhana (jaisa PDF mein tha)
    assign LEDR[0] = pll_locked;
    assign LEDR[9:1] = 9'b0;   // baaki LEDs off (unused)

    // ============================================
    // Horizontal and Vertical Timing Parameters
    // (1024x768 @ 60Hz)
    // ============================================
    parameter H_VISIBLE     = 1024;
    parameter H_FRONT_PORCH = 24;
    parameter H_SYNC_PULSE  = 136;
    parameter H_BACK_PORCH  = 160;
    parameter H_TOTAL       = 1344;  // sum of above

    parameter V_VISIBLE     = 768;
    parameter V_FRONT_PORCH = 3;
    parameter V_SYNC_PULSE  = 6;
    parameter V_BACK_PORCH  = 29;
    parameter V_TOTAL       = 806;   // sum of above

    // ============================================
    // Horizontal and Vertical Counters
    // ============================================
    reg [10:0] h_count;  // needs to count up to 1343, so 11 bits enough
    reg [9:0]  v_count;  // needs to count up to 805, so 10 bits enough

    always @(posedge clk_65mhz or negedge reset_n) begin
        if (!reset_n) begin
            h_count <= 0;
            v_count <= 0;
        end
        else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
            end
            else begin
                h_count <= h_count + 1;
            end
        end
    end

    // ============================================
    // HSYNC and VSYNC Generation
    // ============================================
    wire hsync;
    wire vsync;

    // HSYNC LOW during sync pulse region
    assign hsync = ~((h_count >= (H_VISIBLE + H_FRONT_PORCH)) &&
                      (h_count <  (H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE)));

    // VSYNC LOW during sync pulse region
    assign vsync = ~((v_count >= (V_VISIBLE + V_FRONT_PORCH)) &&
                      (v_count <  (V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE)));

    // ============================================
    // Display Enable (Visible Area Detection)
    // ============================================
    wire display_enable;
    assign display_enable = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

    // ============================================
    // Image Region and ROM Address Calculation
    // ============================================
    parameter IMG_WIDTH  = 128;
    parameter IMG_HEIGHT = 128;
    parameter IMG_X_START = (H_VISIBLE - IMG_WIDTH) / 2;   // horizontally center
    parameter IMG_Y_START = (V_VISIBLE - IMG_HEIGHT) / 2;  // vertically center

    wire in_image_region;
    assign in_image_region = (h_count >= IMG_X_START) && (h_count < IMG_X_START + IMG_WIDTH) &&
                              (v_count >= IMG_Y_START) && (v_count < IMG_Y_START + IMG_HEIGHT);

    wire [13:0] image_addr;
    assign image_addr = (v_count - IMG_Y_START) * IMG_WIDTH + (h_count - IMG_X_START);

    wire [7:0] image_pixel;

    image_rom u_image_rom (
        .address (image_addr),
        .clock   (clk_65mhz),
        .q       (image_pixel)
    );

    // ============================================
    // Pipeline Registers (1-cycle delay to match ROM latency)
    // ============================================
    reg in_image_region_d;
    reg hsync_d, vsync_d, display_enable_d;

    always @(posedge clk_65mhz) begin
        in_image_region_d <= in_image_region;
        hsync_d           <= hsync;
        vsync_d           <= vsync;
        display_enable_d  <= display_enable;
    end

    // ============================================
    // RGB Output Logic (using delayed signals to match ROM output)
    // ============================================
    reg [7:0] red_out, green_out, blue_out;

    always @(*) begin
        if (!display_enable_d) begin
            // Blanking area — kuch nahi dikhana
            red_out   = 8'h00;
            green_out = 8'h00;
            blue_out  = 8'h00;
        end
        else if (in_image_region_d) begin
            // Extract RGB332 components from image_pixel and scale to 8-bit
            red_out   = {image_pixel[7:5], 5'b00000};   // top 3 bits -> red
            green_out = {image_pixel[4:2], 5'b00000};   // middle 3 bits -> green
            blue_out  = {image_pixel[1:0], 6'b000000};  // bottom 2 bits -> blue
        end
        else begin
            // Background color — halka blue
            red_out   = 8'h30;
            green_out = 8'h60;
            blue_out  = 8'hA0;
        end
    end

    assign VGA_R = red_out;
    assign VGA_G = green_out;
    assign VGA_B = blue_out;
    assign VGA_HS = hsync_d;
    assign VGA_VS = vsync_d;
    assign VGA_BLANK_N = display_enable_d;
    assign VGA_SYNC_N  = 1'b0;
    assign VGA_CLK     = clk_65mhz;

endmodule