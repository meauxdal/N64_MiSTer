`timescale 1ns/1ps
module auto_crt_ar_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg reset = 1, ce_pix = 0, use_b = 0;
  reg hsync = 0, vsync = 0, hblank = 1, vblank = 1;
  wire [11:0] arx, ary;
  auto_crt_ar dut(.*);

  task automatic frame(input integer ht, vt, ha, va, vs_offset = 0);
    for (integer y = 0; y < vt; y++) begin
      for (integer x = 0; x < ht; x++) begin
        @(negedge clk);
        ce_pix = 1;
        hsync = x < 8;
        vsync = y * ht + x >= vs_offset && y * ht + x < 3 * ht + vs_offset;
        hblank = x < 100 || x >= 100 + ha;
        vblank = y < 10 || y >= 10 + va;
      end
    end
  endtask

  task automatic check_ratio(input integer ht, vt, ha, va, sn, sd);
    real expected, measured;
    repeat (4) frame(ht, vt, ha, va);
    expected = (real'(ha) * vt * sn) / (real'(ht) * va * sd);
    measured = real'(arx) / ary;
    if (arx == 4 && ary == 3) $fatal(1, "ratio did not update");
    if (measured / expected < 0.998 || measured / expected > 1.002)
      $fatal(1, "ratio %f differs from expected %f", measured, expected);
  endtask

  initial begin
    repeat (3) @(negedge clk);
    reset = 0;
    check_ratio(774, 262, 640, 240, 8192, 5565);
    // Interlaced fields can differ by one line and start VS halfway
    // through a line. They must not make the stable ratio flicker.
    begin
      reg [11:0] old_x, old_y;
      old_x = arx; old_y = ary;
      repeat (2) begin
        frame(774, 263, 640, 240, 387);
        frame(774, 262, 640, 240);
      end
      if (arx != old_x || ary != old_y) $fatal(1, "field timing changed ratio");
    end
    check_ratio(774, 262, 512, 200, 8192, 5565);
    // A one-frame transient must not replace the stable box.
    begin
      reg [11:0] old_x, old_y;
      old_x = arx; old_y = ary;
      frame(774, 262, 320, 120);
      frame(774, 262, 512, 200);
      if (arx != old_x || ary != old_y) $fatal(1, "transient changed ratio");
    end
    @(negedge clk); use_b = 1;
    @(negedge clk);
    if (arx != 4 || ary != 3) $fatal(1, "standard change did not reset ratio");
    check_ratio(795, 312, 640, 288, 3776, 2496);
    check_ratio(795, 312, 400, 240, 3776, 2496);
    $display("PASS: NTSC/PAL, cropping, interlaced fields, transient rejection, standard reset");
    $finish;
  end
endmodule
