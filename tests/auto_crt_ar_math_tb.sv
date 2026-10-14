`timescale 1ns/1ps
module auto_crt_ar_math_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg reset = 1, use_b = 0;
  wire [11:0] arx, ary;
  // Exercise the full supported coefficient width, beyond the default
  // NTSC/PAL constants. Raster tests separately cover frame acquisition.
  auto_crt_ar #(.A_H_VIS_DEN(8'd255), .A_V_VIS_NUM(8'd255),
    .A_H_VIS_NUM(8'd255), .A_V_VIS_DEN(8'd255)) dut
    (.clk(clk), .reset(reset), .use_b(use_b), .ce_pix(1'b0),
     .hsync(1'b0), .vsync(1'b0), .hblank(1'b1), .vblank(1'b1),
     .arx(arx), .ary(ary));

  task automatic check_products(input bit pal, input logic [11:0] ht, vt, ha, va);
    logic [63:0] expected_x, expected_y;
    integer watchdog;
    @(negedge clk); reset = 1; use_b = pal;
    @(negedge clk); reset = 0;
    // Inject a captured geometry snapshot at the arithmetic interface.
    dut.u_htotal = ht; dut.u_vtotal = vt;
    dut.u_hactive = ha; dut.u_vactive = va;
    dut.pending = 1;
    expected_x = 64'(ha) * vt * (pal ? 64'd3776 : 64'd260100);
    expected_y = 64'(ht) * va * (pal ? 64'd2496 : 64'd195075);
    watchdog = 0;
    do begin
      @(negedge clk);
      watchdog++;
      if (watchdog > 80) $fatal(1, "multiplier failed to finish");
    end while (dut.state != dut.S_SHRINK);
    if (dut.num != expected_x || dut.den != expected_y)
      $fatal(1, "products differ: X %d/%d, Y %d/%d", dut.num, expected_x, dut.den, expected_y);
  endtask

  initial begin
    check_products(0, 4095, 4095, 4095, 4095);
    check_products(0, 4095, 1, 1, 4095);
    check_products(0, 0, 4095, 4095, 0);
    check_products(1, 795, 312, 640, 288);
    for (integer i = 0; i < 256; i++)
      check_products(i[0], 12'($urandom), 12'($urandom), 12'($urandom), 12'($urandom));
    $display("PASS: exact serial products, maximum coefficients, boundaries and 256 random geometries");
    $finish;
  end
endmodule
