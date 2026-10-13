library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pVI.all;
entity vi_crop_tb is end;
architecture test of vi_crop_tb is
   signal clk : std_logic := '0';
   signal startOut, newFrame, idle : std_logic := '0';
   signal hstart, hend : unsigned(9 downto 0);
   signal scale, offset : unsigned(11 downto 0);
   signal extent : unsigned(9 downto 0);
begin
   clk <= not clk after 5 ns;
   dut : entity work.VI_outProcess port map (
      clk1x => clk, reset => '0', error_outProcess => open,
      ISPAL => '0', VI_BILINEAROFF => '1', VI_DEBLUR => '0',
      VI_GAMMAOFF => '1', VI_NOISEOFF => '1',
      VI_CTRL_GAMMA_DITHER_ENABLE => '0', VI_CTRL_AA_MODE => "11",
      VI_CTRL_GAMMA_ENABLE => '0', VI_H_VIDEO_START => hstart,
      VI_H_VIDEO_END => hend, VI_X_SCALE_FACTOR => scale, VI_X_SCALE_OFFSET => offset,
      newFrame => newFrame, startOut => startOut, fracYout => "00000",
      outprocIdle => idle, filter_y => '0', filterAddr => open,
      filterData => (others => '0'), line_x_min => open, line_x_max => open,
      line_x_end => extent, out_pixel => open, out_x => open, out_y => open, out_color => open
   );
   process
      procedure check(w, s, o, expected : integer) is
      begin
         hstart <= to_unsigned(108, 10); hend <= to_unsigned(108 + w, 10);
         scale <= to_unsigned(s, 12); offset <= to_unsigned(o, 12);
         wait until falling_edge(clk); startOut <= '1';
         wait until falling_edge(clk); startOut <= '0';
         wait until idle = '1'; wait until falling_edge(clk);
         assert to_integer(extent) = expected report "incorrect cropped source width" severity failure;
      end;
   begin
      check(640, 16#200#, 0, 320);
      check(512, 16#200#, 0, 256);
      check(400, 16#400#, 0, 400);
      check(512, 16#200#, 16#400#, 257);
      report "PASS: full width, horizontal crop, scale and subpixel offset";
      std.env.stop; wait;
   end process;
end;
