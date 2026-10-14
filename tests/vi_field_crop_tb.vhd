library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pVI.all;
entity vi_field_crop_tb is end;
architecture test of vi_field_crop_tb is
   signal clk : std_logic := '0';
   signal reset : std_logic := '1';
   signal settings : tvideoout_settings :=
      ("10", '1', '0', '1', '0', "00", to_unsigned(474,10),
       to_unsigned(525,10), to_unsigned(95,12), to_unsigned(128,10),
       to_unsigned(128,10), to_unsigned(35,10), to_unsigned(509,10),
       to_unsigned(2,8), to_unsigned(3,4));
   signal reports : tvideoout_reports;
   signal video : tvideoout_out;
   signal request : tvideoout_request;
   signal fetch_count, previous_fetch_count : integer := 0;
   signal first_start, first_end : integer := 35;
   signal alternate : boolean := true;
begin
   clk <= not clk after 5 ns;
   dut : entity work.vi_videoout_async generic map (VITEST => '1') port map (
      clk1x => clk, clkvid => clk, ce_1x => '1', reset_1x => reset,
      videoout_settings_1x => settings, videoout_reports_1x => reports,
      videoout_request_1x => request, videoout_readAddr => open,
      videoout_pixelRead => (others => '0'), overlay_xpos => open,
      overlay_ypos => open, overlay_data => (others => '0'), overlay_ena => '0',
      videoout_out => video, SS_VI_CURRENT => (others => '0'),
      SS_nextHCount => (others => '0'));
   process(clk)
      variable shift : integer;
   begin
      if falling_edge(clk) then
         shift := 0;
         if alternate and reports.interlacedDisplayField = '1' then shift := 2; end if;
         settings.VI_V_VIDEO_START <= to_unsigned(first_start + shift, 10);
         settings.VI_V_VIDEO_END <= to_unsigned(first_end + shift, 10);
      end if;
   end process;
   process(clk)
   begin
      if rising_edge(clk) then
         if reset = '1' then
            fetch_count <= 0; previous_fetch_count <= 0;
         elsif request.newFrame = '1' then
            previous_fetch_count <= fetch_count; fetch_count <= 0;
         elsif request.fetch = '1' then
            fetch_count <= fetch_count + 1;
         end if;
      end if;
   end process;
   process
      procedure check_fields(expected_start, expected_end : integer; expected_rows : integer := -1) is
         variable rows : integer;
      begin
         rows := expected_rows;
         if rows < 0 then rows := expected_end - expected_start; end if;
         for f in 1 to 6 loop
            wait until rising_edge(video.vsync);
            wait until falling_edge(video.vblank);
            wait for 60 ns; -- let the reports CDC settle within this line
            if f > 2 then
               assert to_integer(reports.VI_CURRENT) = expected_start
                  report "interlaced active window moves between fields" severity failure;
               assert previous_fetch_count = rows
                  report "display crop changed the field's source fetch window" severity failure;
            end if;
            wait until rising_edge(video.vblank);
            wait for 60 ns;
            if f > 2 then
               assert to_integer(reports.VI_CURRENT) = expected_end
                  report "interlaced active window end moves between fields" severity failure;
            end if;
         end loop;
      end;
   begin
      first_end <= 509;
      wait for 100 ns; reset <= '0';
      check_fields(18, 255); -- captured BattleZone 35:509 / 37:511
      first_start <= 65; first_end <= 385;
      check_fields(33, 193); -- preserve a genuinely different cropped window
      settings.isPAL <= '1'; settings.VI_V_SYNC <= to_unsigned(625,10);
      first_start <= 45; first_end <= 621;
      check_fields(23, 311);
      first_start <= 65; first_end <= 385;
      settings.VI_DIRECTFBMODE <= '0';
      check_fields(23, 311, 160); -- Original VI keeps its existing interlace blanks
      settings.VI_DIRECTFBMODE <= '1'; settings.fixedBlanks <= '1';
      check_fields(23, 311, 160); -- fixed-blank override remains fixed
      settings.fixedBlanks <= '0';
      alternate <= false; settings.CTRL_SERRATE <= '0';
      first_start <= 65; first_end <= 385;
      check_fields(33, 193); -- progressive menus retain programmed crop
      report "PASS: stable field crop, NTSC/PAL, crop changes, legacy/fixed blanks and progressive menus";
      std.env.stop; wait;
   end process;
   process begin
      wait for 20 ms;
      assert false report "field crop watchdog" severity failure;
   end process;
end;
