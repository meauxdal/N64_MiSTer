library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pVI.all;
use work.pFunctions.all;
entity vi_courtside_tb is end;
architecture test of vi_courtside_tb is
   signal clk : std_logic := '0';
   signal reset, newframe, fetch, field : std_logic := '0';
   signal origin : unsigned(23 downto 0) := x"200480";
   signal req, done, sreq, sdone, ready, startproc, procdone, startout, wr : std_logic := '0';
   signal address : unsigned(27 downto 0);
   signal store, ptr : std_logic_vector(2 downto 0);
   signal data, banks : tfetchArray := (others => (others => '0'));
   signal writes : std_logic_vector(87 downto 0);
   signal count : unsigned(9 downto 0);
   signal frameindex : unsigned(1 downto 0) := "00";
   signal requests, starts, completed, pixels : integer := 0;
begin
   clk <= not clk after 8 ns;
   lf : entity work.VI_linefetch port map (
      clk1x=>clk,clk2x=>clk,reset=>reset,VI_DIRECTFBMODE=>'1',VI_DIRECTFB_2LINES=>'0',
      VI_CTRL_TYPE=>"10",VI_CTRL_SERRATE=>'1',VI_ORIGIN=>origin,VI_WIDTH=>to_unsigned(576,12),
      VI_X_SCALE_FACTOR=>x"400",VI_Y_SCALE_FACTOR=>x"800",VI_Y_SCALE_OFFSET=>x"000",
      newFrame=>newframe,fetch=>fetch,interlacedField=>field,video_blockVIFB=>'0',
      startProc=>startproc,procDone=>procdone,outprocIdle=>'1',startOut=>startout,
      FetchLineCount=>count,rdram_request=>req,rdram_address=>address,rdram_granted=>req,
      rdram_done=>done,ddr3_DOUT_READY=>ready,sdram_request=>sreq,sdram_granted=>sreq,
      sdram_done=>sdone,sdram_valid=>'0',error_linefetch=>open,addr9_offset=>open,
      procPtr=>ptr,fracYout=>open,rdram_rnw=>open,rdram_burstcount=>open,
      rdram_store=>store,rdram_storeAddr=>open,sdram_rnw=>open,sdram_address=>open,
      sdram_burstcount=>open,rdram9_store=>open,rdram9_storeAddr=>open);
   lp : entity work.VI_lineProcess port map (
      clk1x=>clk,reset=>reset,VI_DIRECTFBMODE=>'1',VI_CTRL_TYPE=>"10",VI_CTRL_AA_MODE=>"00",
      VI_WIDTH=>to_unsigned(576,12),newFrame=>newframe,startProc=>startproc,
      interlacedField=>field,procDone=>procdone,fetchAddr=>open,fetchdata=>data,
      fetchAddr9=>open,fetchdata9=>(others=>(others=>'0')),proc_pixel=>open,
      proc_border=>open,proc_x=>open,proc_y=>open,proc_pixel_Mid=>open,
      proc_pixels_AA=>open,proc_pixels_DD=>open,video_blockVIFB=>'0',
      line_x_min=>to_unsigned(0,10),line_x_max=>to_unsigned(576,10),
      VIFB_frameindex=>frameindex,VIFBfifo_Din=>writes,VIFBfifo_Wr=>wr);
   process(clk)
      variable delay : integer := 0;
      variable row, red, green, col, y : integer;
      variable tag : unsigned(15 downto 0);
   begin
      if rising_edge(clk) then
         done<='0';sdone<='0';ready<='0';
         if req='1' then delay:=20; requests<=requests+1; end if;
         if delay>0 then
            delay:=delay-1;ready<='1';
            row:=(to_integer(address)-16#200000#)/1152;
            tag:=byteswap16(to_unsigned(row*64+1,16));
            for i in 0 to 2 loop
               if store(i)='1' then banks(i)<=tag & tag; end if;
            end loop;
            if delay=0 then done<='1';sdone<='1';end if;
         end if;
         if ptr(0)='1' then data(2)<=banks(0);
         elsif ptr(1)='1' then data(2)<=banks(1);
         else data(2)<=banks(2);end if;
         if startproc='1' then starts<=starts+1;end if;
         if procdone='1' then completed<=completed+1;end if;
         if wr='1' then
            col:=to_integer(unsigned(writes(72 downto 64)));
            y:=to_integer(unsigned(writes(81 downto 73)));
            if col<288 then
               red:=((y+1)/32)*8;
               green:=((y+1) mod 32)*8;
               assert to_integer(unsigned(writes(39 downto 32)))=red and
                      to_integer(unsigned(writes(7 downto 0)))=red and
                      to_integer(unsigned(writes(47 downto 40)))=green and
                      to_integer(unsigned(writes(15 downto 8)))=green
                  report "framebuffer row contains another source row" severity failure;
               pixels<=pixels+2;
            end if;
         end if;
         if reset='1' then requests<=0;starts<=0;completed<=0;pixels<=0;end if;
      end if;
   end process;
   process
      procedure pulse(signal s:out std_logic) is
      begin
         wait until falling_edge(clk);s<='1';wait until falling_edge(clk);s<='0';
      end;
   begin
      for f in 0 to 1 loop
         reset<='1';wait for 80 ns;wait until falling_edge(clk);reset<='0';
         if f=0 then field<='0';origin<=x"200480";else field<='1';origin<=x"200900";end if;
         frameindex<=to_unsigned(f,2);
         pulse(newframe);
         for line in 1 to 227 loop pulse(fetch);wait for 63520 ns;end loop;
         wait for 64000 ns;
         assert requests=454 and starts=454 and completed=454
            report "source rows fetched but not processed" severity failure;
         assert pixels=454*576 report "incomplete framebuffer" severity failure;
         pulse(newframe);wait for 64 ns;
         assert to_integer(count)=454 report "incorrect title framebuffer height" severity failure;
      end loop;
      report "PASS: Courtside 576x454, Y=0x800, both fields and every framebuffer row";
      std.env.stop;wait;
   end process;
end;
