library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pVI.all;

entity vi_linefetch_tb is end;
architecture test of vi_linefetch_tb is
   signal clk : std_logic := '0';
   signal reset, newFrame, fetch, twoLines, field : std_logic := '0';
   signal width : unsigned(11 downto 0) := to_unsigned(640, 12);
   signal yscale : unsigned(11 downto 0) := x"400";
   signal req, done, sreq, sdone, startProc, procDone, startOut : std_logic := '0';
   signal address : unsigned(27 downto 0);
   signal count : unsigned(9 downto 0);
   signal requests : integer := 0;
   signal firstAddress : unsigned(27 downto 0);
begin
   clk <= not clk after 5 ns;
   dut : entity work.VI_linefetch port map (
      clk1x => clk, clk2x => clk, reset => reset,
      VI_DIRECTFBMODE => '1', VI_DIRECTFB_2LINES => twoLines,
      VI_CTRL_TYPE => "10", VI_CTRL_SERRATE => '1',
      VI_ORIGIN => x"6C2D00", VI_WIDTH => width,
      VI_X_SCALE_FACTOR => x"400", VI_Y_SCALE_FACTOR => yscale,
      VI_Y_SCALE_OFFSET => x"000", newFrame => newFrame, fetch => fetch,
      interlacedField => field, video_blockVIFB => '0',
      startProc => startProc, procDone => procDone, outprocIdle => '1',
      startOut => startOut, FetchLineCount => count,
      rdram_request => req, rdram_address => address,
      rdram_granted => req, rdram_done => done, ddr3_DOUT_READY => '0',
      sdram_request => sreq, sdram_granted => sreq,
      sdram_done => sdone, sdram_valid => '0',
      error_linefetch => open, addr9_offset => open, procPtr => open,
      fracYout => open, rdram_rnw => open, rdram_burstcount => open,
      rdram_store => open, rdram_storeAddr => open, sdram_rnw => open,
      sdram_address => open, sdram_burstcount => open,
      rdram9_store => open, rdram9_storeAddr => open
   );
   process(clk)
   begin
      if rising_edge(clk) then
         done <= req;
         sdone <= sreq;
         procDone <= startProc;
         if reset = '1' then
            requests <= 0;
         elsif req = '1' then
            if requests = 0 then firstAddress <= address; end if;
            requests <= requests + 1;
         end if;
      end if;
   end process;
   process
      procedure pulse(signal value : out std_logic) is
      begin
         wait until falling_edge(clk); value <= '1';
         wait until falling_edge(clk); value <= '0';
      end;
      procedure check(paired : std_logic; odd : std_logic; pitch, scale, rows : integer) is
         variable expected : integer;
      begin
         reset <= '1'; twoLines <= paired; field <= odd;
         width <= to_unsigned(pitch, 12); yscale <= to_unsigned(scale, 12);
         wait for 40 ns; wait until falling_edge(clk); reset <= '0';
         pulse(newFrame);
         for i in 1 to 5 loop
            pulse(fetch);
            wait for 1000 ns;
         end loop;
         assert requests = rows report "incorrect number of source rows" severity failure;
         expected := 16#6C2D00#;
         if paired = '1' and odd = '1' then expected := expected - pitch * 2; end if;
         assert to_integer(firstAddress) = expected report "incorrect field origin" severity failure;
         pulse(newFrame); wait for 40 ns;
         assert to_integer(count) = rows report "incorrect framebuffer height" severity failure;
      end;
   begin
      -- BattleZone mission: 640-pixel stride, SERRATE, X/Y_SCALE=0x400.
      check('0', '0', 640, 16#400#, 5);
      check('0', '1', 640, 16#400#, 5);
      -- Preserve the existing reconstruction when the caller halves stride.
      check('1', '0', 320, 16#400#, 10);
      check('1', '1', 320, 16#400#, 10);
      -- Two rows are still required when Y scale itself advances by two.
      check('0', '0', 640, 16#800#, 10);
      report "PASS: BattleZone fields, halved stride, vertical downscale";
      std.env.stop;
      wait;
   end process;
end;
