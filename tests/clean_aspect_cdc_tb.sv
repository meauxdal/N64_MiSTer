`timescale 1ns/1ps
module clean_aspect_cdc_tb;
 reg clk = 0, run_clk = 1;
 always #5 if (run_clk) clk = ~clk;
 reg reset_async = 1, enabled_async = 0, pal_async = 0;
 wire reset, pal;
 clean_aspect_cdc dut(.*);

 task automatic tick;
  @(posedge clk); #1;
 endtask

 initial begin
  tick();
  @(negedge clk); reset_async = 0; enabled_async = 1; pal_async = 1;
  tick();
  if (!reset || pal) $fatal(1, "control escaped first stage");
  tick();
  if (reset || !pal) $fatal(1, "controls did not reach second stage");
  @(negedge clk); enabled_async = 0; pal_async = 0;
  tick();
  if (reset || !pal) $fatal(1, "disable/PAL escaped first stage");
  tick();
  if (!reset || pal) $fatal(1, "disable/PAL did not reach second stage");
  @(negedge clk); enabled_async = 1;
  repeat (2) tick();
  if (reset) $fatal(1, "enable did not release reset");

  // A reset pulse shorter than a clock period must still be caught,
  // including while the video PLL supplies no edges.
  @(negedge clk); run_clk = 0;
  #1; reset_async = 1;
  #1;
  if (!reset) $fatal(1, "reset did not assert without clock");
  reset_async = 0;
  #20;
  if (!reset) $fatal(1, "reset released without clock");
  run_clk = 1;
  tick();
  if (!reset) $fatal(1, "reset released before second edge");
  tick();
  if (reset) $fatal(1, "reset failed to release on second edge");
  $display("PASS: CDC latency, disable, PAL, stopped-clock reset and synchronous release");
  $finish;
 end
endmodule
