library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity vi_static_mode_tb is end;
architecture test of vi_static_mode_tb is
   signal clk : std_logic := '0';
   signal reset, ssreset, bw, br : std_logic := '0';
   signal ba : unsigned(19 downto 0) := (others=>'0');
   signal din, dout : std_logic_vector(31 downto 0) := (others=>'0');
   signal base : unsigned(31 downto 0);
   signal sx, sy : unsigned(9 downto 0);
   signal req, sreq, done, sdone, wr : std_logic := '0';
   signal fb : std_logic_vector(87 downto 0);
   signal burst : unsigned(9 downto 0);
   signal check_rows : boolean := false;
   signal lastrow : integer := -1;
   signal rowstarts : integer := 0;
begin
   clk <= not clk after 8 ns;
   dut : entity work.VI generic map (use2Xclock=>'0', VITEST=>'1') port map (
      clk1x=>clk,clk2x=>clk,clkvid=>clk,ce=>'1',reset_1x=>reset,
      ISPAL=>'0',FIXEDBLANKS=>'0',CROPVERTICAL=>"00",VI_BILINEAROFF=>'1',
      VI_DEBLUR=>'0',VI_GAMMAOFF=>'1',VI_NOISEOFF=>'1',VI_DEDITHEROFF=>'1',
      VI_DEDITHERFORCE=>'0',VI_AAOFF=>'1',VI_DIVOTOFF=>'1',VI_7BITPERCOLOR=>'0',
      VI_DIRECTFBMODE=>'1',errorEna=>'0',errorCode=>x"00000000",fpscountOn=>'0',
      rdram_request=>req,rdram_rnw=>open,rdram_address=>open,rdram_burstcount=>burst,
      rdram_granted=>req,rdram_done=>done,ddr3_DOUT=>x"0000000000000000",ddr3_DOUT_READY=>'0',
      VIFBfifo_Din=>fb,VIFBfifo_Wr=>wr,sdram_request=>sreq,sdram_rnw=>open,
      sdram_address=>open,sdram_burstcount=>open,sdram_granted=>sreq,sdram_done=>sdone,
      sdram_dataRead=>x"00000000",sdram_valid=>'0',
      video_hsync=>open,video_vsync=>open,video_hblank=>open,video_vblank=>open,
      video_ce=>open,video_interlace=>open,video_r=>open,video_g=>open,video_b=>open,
      video_FB_en=>open,video_FB_base=>base,video_FB_sizeX=>sx,video_FB_sizeY=>sy,
      bus_addr=>ba,bus_dataWrite=>din,bus_read=>br,bus_write=>bw,bus_dataRead=>dout,bus_done=>open,
      SS_reset=>ssreset,SS_DataWrite=>(others=>'0'),SS_Adr=>"000",SS_wren=>'0',SS_rden=>'0',SS_DataRead=>open);
   process(clk)
      variable delay : natural := 0;
      variable row : integer;
   begin
      if rising_edge(clk) then
         done<='0';sdone<='0';
         if req='1' then delay:=20; end if;
         if delay>0 then
            delay:=delay-1;
            if delay=0 then done<='1';sdone<='1';end if;
         end if;
         if not check_rows then lastrow<=-1;rowstarts<=0;
         elsif wr='1' and unsigned(fb(72 downto 64))=0 then
            row:=to_integer(unsigned(fb(81 downto 73)));
            assert row=lastrow+1 report "static title framebuffer rows skip or wrap" severity failure;
            lastrow<=row;rowstarts<=rowstarts+1;
         end if;
      end if;
   end process;
   process
      procedure put(addr, value : natural) is
      begin
         wait until falling_edge(clk);ba<=to_unsigned(addr,20);din<=std_logic_vector(to_unsigned(value,32));bw<='1';
         wait until falling_edge(clk);bw<='0';wait for 64 ns;
      end;
      procedure get_current(variable current : out natural) is
      begin
         wait until falling_edge(clk);ba<=x"00010";br<='1';
         wait until falling_edge(clk);current:=to_integer(unsigned(dout(9 downto 0)));br<='0';
      end;
      procedure field_start is
         variable current, previous : natural;
      begin
         get_current(previous);
         loop
            wait for 128 ns;get_current(current);
            exit when current<previous;
            previous:=current;
         end loop;
      end;
      variable a, b : unsigned(31 downto 0);
   begin
      ssreset<='1';wait for 64 ns;ssreset<='0';reset<='1';wait for 64 ns;reset<='0';
      put(0,16#42#);put(4,16#200480#);put(8,576);
      -- Short blank fields warm the actual VI detector past its 30-field timeout.
      put(16#18#,31);put(16#1c#,127);put(16#24#,140*65536+716);
      put(16#28#,10*65536+10);put(16#30#,16#400#);put(16#34#,16#800#);
      for f in 0 to 39 loop
         field_start;
         if f mod 2=0 then put(4,16#200900#);else put(4,16#200480#);end if;
      end loop;
      wait for 10 us;a:=base;field_start;wait for 10 us;b:=base;
      assert a/=b report "Y=0x800 title incorrectly switches to static-field weaving" severity failure;
      -- Restore the captured raster and check the first complete field after settling.
      put(16#1c#,16#c15#);put(16#18#,16#20d#);put(16#28#,45*65536+499);
      field_start;field_start;check_rows<=true;field_start;
      assert rowstarts=454 and lastrow=453
         report "static title row count=" & integer'image(rowstarts) & ", last=" & integer'image(lastrow)
         severity failure;
      check_rows<=false;wait for 64 ns;
      -- A one-row-per-line static interlaced source must retain field weaving.
      put(16#28#,10*65536+10);put(16#18#,31);put(16#1c#,127);put(16#34#,16#400#);
      for f in 0 to 39 loop field_start;end loop;
      wait for 10 us;a:=base;field_start;wait for 10 us;
      assert base=a and base=x"31000000" report "one-row static field weaving regressed" severity failure;
      -- Switching back must leave weave mode, even without an origin page change.
      put(16#34#,16#800#);field_start;field_start;wait for 10 us;a:=base;
      field_start;wait for 10 us;
      assert base/=a report "transition out of static-field weaving failed" severity failure;
      report "PASS: static title timeout, 454 contiguous rows, one-row weaving and scale transition";
      std.env.stop;wait;
   end process;
   process begin wait for 100 ms;assert false report "mode test timeout" severity failure;end process;
end;
