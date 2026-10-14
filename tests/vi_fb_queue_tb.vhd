library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pDDR3.all;
entity vi_fb_queue_tb is end;
architecture test of vi_fb_queue_tb is
   signal clk : std_logic := '0';
   signal requests : tDDDR3Single := (others=>'0');
   signal wr, we : std_logic := '0';
   signal input : std_logic_vector(87 downto 0) := (others=>'0');
   signal output : std_logic_vector(63 downto 0);
   signal address : std_logic_vector(28 downto 0);
   signal received : integer := 0;
   signal other_received : integer := 0;
   signal busy : std_logic := '0';
begin
   clk<=not clk after 4 ns;
   dut : entity work.DDR3Mux generic map (use2Xclock=>'0') port map (
      clk1x=>clk,clk2x=>clk,clk2xIndex=>'1',RAMSIZE8=>'1',slow_in=>"0000",
      error=>open,error_fifo=>open,error_outReq=>open,error_outRSP=>open,
      error_outRDP=>open,error_outRDPZ=>open,error_outPI=>open,
      ddr3_BUSY=>busy,ddr3_DOUT=>(others=>'0'),ddr3_DOUT_READY=>'0',
      ddr3_BURSTCNT=>open,ddr3_ADDR=>address,ddr3_DIN=>output,ddr3_BE=>open,ddr3_WE=>we,ddr3_RD=>open,
      rdram_request=>requests,rdram_rnw=>(others=>'0'),
      rdram_address=>(others=>(others=>'0')),rdram_burstcount=>(others=>to_unsigned(1,10)),
      rdram_writeMask=>(others=>(others=>'1')),rdram_dataWrite=>(others=>(others=>'0')),
      rdram_granted=>open,rdram_granted2X=>open,rdram_done=>open,rdram_dataRead=>open,
      rspfifo_req=>'0',rspfifo_reset=>'0',rspfifo_Din=>(others=>'0'),rspfifo_Wr=>'0',
      rspfifo_nearfull=>open,rspfifo_empty=>open,
      rdpfifo_Din=>(others=>'0'),rdpfifo_Wr=>'0',rdpfifo_nearfull=>open,rdpfifo_empty=>open,
      rdpfifoZ_Din=>(others=>'0'),rdpfifoZ_Wr=>'0',rdpfifoZ_nearfull=>open,rdpfifoZ_empty=>open,
      PIfifo_Din=>(others=>'0'),PIfifo_Wr=>'0',PIfifo_nearfull=>open,PIfifo_empty=>open,
      VIFBfifo_Din=>input,VIFBfifo_Wr=>wr);
   process(clk)
      variable busy_cycles : integer := 0;
   begin
      if rising_edge(clk) then
         if busy_cycles>0 then
            busy_cycles:=busy_cycles-1;
            if busy_cycles=0 then busy<='0';end if;
         elsif we='1' then
            busy_cycles:=2;busy<='1'; -- exercise request holding during DDR busy
            if unsigned(address(24 downto 0))>=16#200000# then
               assert unsigned(output)=received+1 report "framebuffer write lost or reordered" severity failure;
               received<=received+1;
            else other_received<=other_received+1;end if;
         end if;
      end if;
   end process;
   process
   begin
      wait for 100 ns;
      requests(DDR3MUX_MEMMUX)<='1'; -- sustained higher-priority traffic
      requests(DDR3MUX_RDP)<='1';
      for word in 1 to 3000 loop
         wait until falling_edge(clk);
         input<=std_logic_vector(to_unsigned(16#200000#+word,24)) & std_logic_vector(to_unsigned(word,64));
         wr<='1';
         wait until falling_edge(clk);wr<='0';
         for delay in 1 to 2 loop wait until falling_edge(clk);end loop;
      end loop;
      requests(DDR3MUX_MEMMUX)<='0';
      requests(DDR3MUX_RDP)<='0';
      wait for 60000 ns;
      assert received=3000 report "framebuffer FIFO overflow under DDR contention: received " & integer'image(received) severity failure;
      assert other_received>1000 report "framebuffer arbitration starved the other clients" severity failure;
      report "PASS: all 3000 framebuffer writes survive sustained DDR contention";
      std.env.stop;wait;
   end process;
end;
