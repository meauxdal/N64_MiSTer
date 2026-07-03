library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use STD.textio.all;

library mem;
use work.pFunctions.all;

entity PI is
   port 
   (
      clk1x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      second_ena           : in  std_logic;
      
      FASTROM              : in  std_logic;
      SAVETYPE             : in  std_logic_vector(2 downto 0); -- 0 -> None, 1 -> EEPROM4, 2 -> EEPROM16, 3 -> SRAM32, 4 -> SRAM96, 5 -> Flash
      fastDecay            : in  std_logic;
      cartAvailable        : in  std_logic;
      cartSize             : in  unsigned(26 downto 0);
      ddDiskAvailable      : in  std_logic;
      ddIplAvailable       : in  std_logic;
      ddDevMode            : in  std_logic;
      hpsRTC               : in  std_logic_vector(64 downto 0);

      irq_out              : out std_logic := '0';
      dd_irq_out           : out std_logic := '0';
      
      error_PI             : out std_logic := '0';
      
      change_sram          : out std_logic := '0';
      change_flash         : out std_logic := '0';
      
      sdram_request        : out std_logic := '0';
      sdram_rnw            : out std_logic := '0'; 
      sdram_address        : out unsigned(26 downto 0):= (others => '0');
      sdram_burstcount     : out unsigned(7 downto 0):= (others => '0');
      sdram_writeMask      : out std_logic_vector(3 downto 0) := (others => '0'); 
      sdram_dataWrite      : out std_logic_vector(31 downto 0) := (others => '0');
      sdram_done           : in  std_logic;
      sdram_dataRead       : in  std_logic_vector(31 downto 0);
      
      rdram_request        : out std_logic := '0';
      rdram_rnw            : out std_logic := '0'; 
      rdram_address        : out unsigned(27 downto 0):= (others => '0');
      rdram_burstcount     : out unsigned(9 downto 0):= (others => '0');
      rdram_done           : in  std_logic;
      rdram_dataRead       : in  std_logic_vector(63 downto 0);

      ddram_request        : out std_logic := '0';
      ddram_rnw            : out std_logic := '0';
      ddram_address        : out unsigned(27 downto 0):= (others => '0');
      ddram_burstcount     : out unsigned(9 downto 0):= (others => '0');
      ddram_writeMask      : out std_logic_vector(7 downto 0) := (others => '0');
      ddram_dataWrite      : out std_logic_vector(63 downto 0) := (others => '0');
      ddram_done           : in  std_logic;
      ddram_dataRead       : in  std_logic_vector(63 downto 0);
      
      PIfifo_Din           : out std_logic_vector(92 downto 0); -- 64bit data + 24 bit address + 8 byte enables
      PIfifo_Wr            : out std_logic;  
      PIfifo_nearfull      : in  std_logic;
      PIfifo_empty         : in  std_logic;
      
      bus_reg_addr         : in  unsigned(19 downto 0); 
      bus_reg_dataWrite    : in  std_logic_vector(31 downto 0);
      bus_reg_read         : in  std_logic;
      bus_reg_write        : in  std_logic;
      bus_reg_dataRead     : out std_logic_vector(31 downto 0) := (others => '0');
      bus_reg_done         : out std_logic := '0';
      
      bus_cart_addr        : in  unsigned(31 downto 0); 
      bus_cart_dataWrite   : in  std_logic_vector(31 downto 0);
      bus_cart_read        : in  std_logic;
      bus_cart_write       : in  std_logic;
      bus_cart_dataRead    : out std_logic_vector(31 downto 0) := (others => '0');
      bus_cart_done        : out std_logic := '0';
      
      SS_reset              : in  std_logic;
      SS_DataWrite          : in  std_logic_vector(63 downto 0);
      SS_Adr                : in  unsigned(2 downto 0);
      SS_wren               : in  std_logic;
      SS_rden               : in  std_logic;
      SS_DataRead           : out std_logic_vector(63 downto 0);
      SS_idle               : out std_logic
   );
end entity;

architecture arch of PI is

   signal PI_DRAM_ADDR           : unsigned(23 downto 0);  -- 0x04600000 PI DRAM address (RW) : [23:0] starting RDRAM address
   signal PI_CART_ADDR           : unsigned(31 downto 0);  -- 0x04600004 PI pbus (cartridge) address (RW) : [31:0] starting AD16 address
   signal PI_LEN                 : unsigned(24 downto 0);  -- 0x04600008/C PI read/write length (RW) : [23:0] read data length
   signal PI_WR_LEN              : unsigned( 6 downto 0);  -- 0x0460000C PI write length (RW) : [23:0] read data length
   signal PI_STATUS_DMAbusy      : std_logic;              -- 0x04600010 PI status (R) : [0] DMA busy [1] I/O busy [2] DMA error [3] Interrupt (DMA completed) (W) : [0] reset controller [1] clear intr
   signal PI_STATUS_IObusy       : std_logic;  
   signal PI_STATUS_DMAerror     : std_logic;  
   signal PI_STATUS_irq          : std_logic;  
   signal PI_BSD_DOM1_LAT        : unsigned(7 downto 0);   -- 0x04600014 PI dom1 latency (RW) : [7:0] domain 1 device latency
   signal PI_BSD_DOM1_PWD        : unsigned(7 downto 0);   -- 0x04600018 PI dom1 pulse width (RW) : [7:0] domain 1 device R / W strobe pulse width
   signal PI_BSD_DOM1_PGS        : unsigned(3 downto 0);   -- 0x0460001C PI dom1 page size(RW) : [3:0] domain 1 device page size
   signal PI_BSD_DOM1_RLS        : unsigned(1 downto 0);   -- 0x04600020 PI dom1 release (RW) : [1:0] domain 1 device R / W release duration
   signal PI_BSD_DOM2_LAT        : unsigned(7 downto 0);   -- 0x04600024 PI dom2 latency (RW) : [7:0] domain 2 device latency
   signal PI_BSD_DOM2_PWD        : unsigned(7 downto 0);   -- 0x04600028 PI dom2 pulse width (RW) : [7:0] domain 2 device R / W strobe pulse width
   signal PI_BSD_DOM2_PGS        : unsigned(3 downto 0);   -- 0x0460002C PI dom2 page size (RW) : [3:0] domain 2 device page size
   signal PI_BSD_DOM2_RLS        : unsigned(1 downto 0);   -- 0x04600030 PI dom2 release (RW) : [1:0] domain 2 device R / W release duration
   
   signal dmaIsWrite             : std_logic;
   signal first128               : std_logic;
   signal blocklength            : integer range 0 to 128;
   signal maxram                 : integer range -7 to 128;
   signal copycnt                : integer range 0 to 128;
   signal MaxBlockSize           : integer range 0 to 128;
   signal distEndOfRow           : integer range 0 to 2048;
   signal distEndOfRowSave       : integer range 0 to 2048;
   signal misAlignSave           : integer range 0 to 7;
      
   -- PI state machine  
   type tState is 
   (  
      IDLE, 
      READROM,
      READSRAM,
      WRITESRAM,
      WRITEFLASH,
      WAITFLASH,
      COPYDMABLOCK,
      DMA_READCART,
      DMA_READDD,
      DMA_READDD_WAIT,
      DMA_READDD_DATA,
      DMA_READRDRAM,
      DMA_WAITRDRAM,
      DMA_WAITSDRAM,
      DD_REG_READ,
      DD_REG_READ_WAIT,
      DD_IPL_RD_WAIT,
      DD_LOAD_REQ,
      DD_LOAD_WAIT,
      DD_STORE_READ,
      DD_STORE_REQ,
      DD_STORE_ISSUE,
      DD_STORE_WAIT,
      DD_DIRTY_WRITE,
      DD_DIRTY_WAIT
   );
   signal state                  : tState := IDLE;
   
   signal writtenData            : std_logic_vector(31 downto 0) := (others => '0');   
   signal writtenTime            : integer range 0 to 200 := 0; 

   signal bus_cart_read_latched  : std_logic := '0';  
   signal bus_cart_write_latched : std_logic := '0';  
   
   signal dma_isflashread        : std_logic := '0';
   signal dma_is_ipl             : std_logic := '0';  -- current PI DMA beat sources the DDR IPL copy
   signal dd_ipl_rd_half         : std_logic := '0';  -- direct IPL read: which 32-bit half of the DDR word

   signal PI_BSD_LAT             : unsigned(7 downto 0);
   signal PI_BSD_PWD             : unsigned(7 downto 0);
   signal PI_BSD_PGS             : unsigned(3 downto 0);
   signal PI_BSD_RLS             : unsigned(1 downto 0);
   signal rom_slow_sum           : unsigned(31 downto 0) := (others => '0');
   signal rom_slow_cnt           : unsigned(31 downto 0) := (others => '0');
   signal PI_DRAM_pagemask       : unsigned(17 downto 0);
   signal PI_DRAM_page           : unsigned(17 downto 0);
   signal PI_DRAM_valid          : std_logic := '0';

   -- Flash
   type tFlashState is 
   (  
      FLASHIDLE, 
      FLASHSTATUS,
      FLASHERASE,
      FLASHREAD,
      FLASHWRITE
   ); 
   signal flashState       : tFlashState := FLASHIDLE;
   signal flash_statusword : std_logic_vector(63 downto 0) := (others => '0');
   signal flash_offset     : unsigned(9 downto 0) := (others => '0');

   signal flash_addrA      : std_logic_vector(5 downto 0) := (others => '0');
   signal flash_DataInA    : std_logic_vector(15 downto 0) := (others => '0');
   signal flash_wrenA      : std_logic := '0';
   signal flash_addrB      : std_logic_vector(4 downto 0) := (others => '0');
   signal flash_DataOutB   : std_logic_vector(31 downto 0);

   -- 64DD / SummerCart64-compatible register surface and sector buffer.
   -- The IPL window is served from the SDRAM boot-staged copy, matching normal ROM fetches.
   constant DD_DISK_DDR_BASE    : unsigned(27 downto 0) := to_unsigned(16#6000000#, 28); -- MiSTer load address 0x36000000
   -- Dedicated DDR copy of the 64DD IPL ROM (MiSTer load address 0x33BC0000).
   -- The N64-visible 0x06000000..0x063FFFFF aperture is served from here so cart
   -- expansion mode (e.g. F-Zero Expansion Kit) does not fetch stale data from the
   -- SDRAM ROM fastload area, which holds the cartridge ROM rather than the IPL.
   constant DD_IPL_DDR_BASE     : unsigned(27 downto 0) := to_unsigned(16#3BC0000#, 28); -- MiSTer load address 0x33BC0000
   constant DD_DISK_HEAD_STRIDE : unsigned(27 downto 0) := to_unsigned(16#3714000#, 28);
   constant DD_DISK_BLOCK_STRIDE: unsigned(27 downto 0) := to_unsigned(16#0006000#, 28);
   constant DD_BAD_BLOCK_SENTINEL: std_logic_vector(63 downto 0) := x"DDDDDDDDDDDDDDDD";
   -- Per-block dirty marker for Main_MiSTer disk write-back. Block slots are
   -- 0x6000 bytes but only 0x000..0x54FF hold sector data, so 0x5F00 is free.
   constant DD_DIRTY_FLAG_OFFSET : unsigned(27 downto 0) := to_unsigned(16#5F00#, 28);
   constant DD_DIRTY_MAGIC       : std_logic_vector(63 downto 0) := x"D1D1D1D1D1D1D1D1";
   -- Ares expresses these delays on the N64's 187.5 MHz system timeline.
   -- Its next-sector event includes work that PI_DD performs serially through
   -- the PI/DDR path, so use the measured residual delay needed to match the
   -- real drive's end-to-end sector cadence. The initial delay only needs the
   -- 187.5-to-62.5 MHz clock-domain conversion.
   constant DD_BM_NEXT_DELAY_CLK1X : unsigned(15 downto 0) := to_unsigned(6849, 16);
   constant DD_BM_START_DELAY_CLK1X: unsigned(15 downto 0) := to_unsigned(16667, 16);
   -- ares track geometry: 85 user sectors, last C2 sector index, block 1 sector base.
   constant DD_SECTOR_USER_END  : unsigned(7 downto 0) := to_unsigned(16#55#, 8);
   constant DD_SECTOR_C2_LAST   : unsigned(7 downto 0) := to_unsigned(16#58#, 8);
   constant DD_SECTOR_BLOCK_BASE: unsigned(7 downto 0) := to_unsigned(16#5A#, 8);
   -- SummerCart64 delays the first seek until its 2-second spin-up timer elapses.
   -- Later seeks still cross the MCU service loop, so avoid completing them in one HDL tick.
   constant DD_SEEK_DELAY_CLK1X: unsigned(27 downto 0) := to_unsigned(1000000, 28);
   constant DD_SEEK_SPINUP_DELAY_CLK1X: unsigned(27 downto 0) := to_unsigned(125000000, 28);

   signal dd_sector_addr_a    : std_logic_vector(4 downto 0) := (others => '0');
   signal dd_sector_data_a0   : std_logic_vector(15 downto 0) := (others => '0');
   signal dd_sector_data_a1   : std_logic_vector(15 downto 0) := (others => '0');
   signal dd_sector_data_a2   : std_logic_vector(15 downto 0) := (others => '0');
   signal dd_sector_data_a3   : std_logic_vector(15 downto 0) := (others => '0');
   signal dd_sector_wren_a    : std_logic := '0';
   signal dd_sector_addr_b    : std_logic_vector(4 downto 0) := (others => '0');
   signal dd_sector_data_in_b0: std_logic_vector(15 downto 0) := (others => '0');
   signal dd_sector_data_in_b1: std_logic_vector(15 downto 0) := (others => '0');
   signal dd_sector_data_in_b2: std_logic_vector(15 downto 0) := (others => '0');
   signal dd_sector_data_in_b3: std_logic_vector(15 downto 0) := (others => '0');
   signal dd_sector_data_out_b0: std_logic_vector(15 downto 0);
   signal dd_sector_data_out_b1: std_logic_vector(15 downto 0);
   signal dd_sector_data_out_b2: std_logic_vector(15 downto 0);
   signal dd_sector_data_out_b3: std_logic_vector(15 downto 0);
   signal dd_sector_data_out_a0: std_logic_vector(15 downto 0);
   signal dd_sector_data_out_a1: std_logic_vector(15 downto 0);
   signal dd_sector_data_out_a2: std_logic_vector(15 downto 0);
   signal dd_sector_data_out_a3: std_logic_vector(15 downto 0);
   signal dd_sector_wren_b    : std_logic_vector(3 downto 0) := (others => '0');
   signal dd_reg_read_offset  : unsigned(10 downto 0) := (others => '0');

   signal dd_hard_reset       : std_logic := '1';
   signal dd_disk_inserted    : std_logic := '0';
   signal dd_disk_changed     : std_logic := '0';
   signal dd_disk_available_d : std_logic := '0';
   signal dd_head_retracted   : std_logic := '1';
   signal dd_spindle_stopped  : std_logic := '1';
   signal dd_motor_started    : std_logic := '0';
   signal dd_index_lock       : std_logic := '0';
   signal dd_data             : std_logic_vector(15 downto 0) := (others => '0');
   signal dd_rtc_year_month   : std_logic_vector(15 downto 0) := x"9601";
   signal dd_rtc_day_hour     : std_logic_vector(15 downto 0) := x"0100";
   signal dd_rtc_minute_second: std_logic_vector(15 downto 0) := x"0000";
   signal dd_rtc_seeded       : std_logic := '0';
   signal dd_cmd_pending      : std_logic := '0';
   signal dd_cmd_interrupt    : std_logic := '0';
   signal dd_bm_interrupt     : std_logic := '0';
   signal dd_bm_transfer_data : std_logic := '0';
   signal dd_bm_transfer_c2   : std_logic := '0';
   signal dd_bm_micro_error   : std_logic := '0';
   signal dd_bm_c1_single     : std_logic := '0';
   signal dd_bm_c1_double     : std_logic := '0';
   signal dd_bm_running       : std_logic := '0';
   signal dd_bm_read_mode     : std_logic := '0';
   signal dd_bm_blocks        : std_logic := '0';
   signal dd_bm_reset_latched : std_logic := '0';
   signal dd_bm_stop_reason   : std_logic_vector(3 downto 0) := (others => '0');
   -- ares-style track-absolute current sector: 0x00..0x58 block 0, 0x5A..0xB2 block 1.
   signal dd_current_sector   : unsigned(7 downto 0) := (others => '0');
   -- single BM request timer; armed by BM start writes and ASIC_STATUS interrupt ACKs.
   signal dd_sector_advance_pending : std_logic := '0';
   signal dd_sector_advance_counter : unsigned(15 downto 0) := (others => '0');
   signal dd_sector_size      : unsigned(7 downto 0) := x"E7";
   signal dd_sector_size_full : unsigned(7 downto 0) := x"E7";
   signal dd_sectors_in_block : unsigned(7 downto 0) := x"59";
   signal dd_head_track       : unsigned(12 downto 0) := (others => '0');
   signal dd_seek_pending     : std_logic := '0';
   signal dd_seek_counter     : unsigned(27 downto 0) := (others => '0');
   signal dd_seek_target      : unsigned(12 downto 0) := (others => '0');
   signal dd_load_addr        : unsigned(27 downto 0) := (others => '0');
   signal dd_load_count       : integer range 0 to 31 := 0;
   signal dd_load_total       : integer range 0 to 32 := 0;
   signal dd_store_addr       : unsigned(27 downto 0) := (others => '0');
   signal dd_store_count      : integer range 0 to 31 := 0;
   signal dd_store_next_sector: unsigned(7 downto 0) := (others => '0');
   signal dd_store_set_data   : std_logic := '0';
   signal dd_store_stop       : std_logic := '0';
   signal dd_write_sector_ready: std_logic := '0';
   signal dd_dirty_addr       : unsigned(27 downto 0) := (others => '0');
   signal dd_cmd_interrupt_visible : std_logic;
   signal dd_attached        : std_logic;
   subtype dd_byte is std_logic_vector(7 downto 0);

   -- savestates
   type t_ssarray is array(0 to 7) of std_logic_vector(63 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  
   signal ss_out : t_ssarray := (others => (others => '0'));     

   function dd_reg_selected(address : unsigned) return boolean is
   begin
      return (address >= to_unsigned(16#05000000#, address'length)) and
             (address <  to_unsigned(16#05010000#, address'length));
   end function;

   function dd_ipl_selected(address : unsigned) return boolean is
   begin
      return (address >= to_unsigned(16#06000000#, address'length)) and
             (address <  to_unsigned(16#06400000#, address'length));
   end function;

   function dd_bcd_to_int(value : dd_byte) return integer is
   begin
      return (to_integer(unsigned(value(7 downto 4))) * 10) + to_integer(unsigned(value(3 downto 0)));
   end function;

   function dd_int_to_bcd(value : integer) return dd_byte is
      variable clamped : integer;
   begin
      clamped := value;
      if (clamped < 0) then
         clamped := 0;
      elsif (clamped > 99) then
         clamped := 99;
      end if;
      return std_logic_vector(to_unsigned(((clamped / 10) * 16) + (clamped mod 10), 8));
   end function;

   function dd_is_bcd(value : dd_byte) return boolean is
   begin
      return (to_integer(unsigned(value(3 downto 0))) <= 9) and
             (to_integer(unsigned(value(7 downto 4))) <= 9);
   end function;

   function dd_days_in_month(year : integer; month : integer) return integer is
      variable days : integer;
   begin
      days := 31;
      case month is
         when 4 | 6 | 9 | 11 =>
            days := 30;
         when 2 =>
            days := 28;
            if ((year mod 4) = 0) then
               days := 29;
            end if;
         when others =>
            days := 31;
      end case;
      return days;
   end function;

   function dd_sector_ddr_address(
      head_track  : unsigned(12 downto 0);
      block_sel   : std_logic;
      sector_num  : unsigned(7 downto 0)
   ) return unsigned is
      variable address  : unsigned(27 downto 0);
      variable sector_i : unsigned(7 downto 0);
   begin
      sector_i := sector_num;
      if (sector_i >= to_unsigned(90, sector_i'length)) then
         sector_i := sector_i - to_unsigned(90, sector_i'length);
      end if;
      if (sector_i > to_unsigned(84, sector_i'length)) then
         sector_i := to_unsigned(84, sector_i'length);
      end if;

      address := DD_DISK_DDR_BASE
         + ('0' & head_track(11 downto 0) & 15x"0")
         + ("00" & head_track(11 downto 0) & 14x"0")
         + (12x"0" & sector_i & 8x"0");
      if (head_track(12) = '1') then address := address + DD_DISK_HEAD_STRIDE; end if;
      if (block_sel = '1') then address := address + DD_DISK_BLOCK_STRIDE; end if;

      return address;
   end function;

   function dd_asic_reg_offset(offset : unsigned(10 downto 0)) return unsigned is
      variable reg_offset : unsigned(10 downto 0);
      variable low_offset : unsigned(6 downto 0);
   begin
      reg_offset := offset;
      if (offset >= 11x"500") then
         low_offset := offset(6 downto 0);
         low_offset(0) := '0';
         reg_offset := 11x"500" + resize(low_offset, 11);
      end if;
      return reg_offset;
   end function;

   function dd_is_cmd_status_offset(offset : unsigned(10 downto 0)) return boolean is
   begin
      return dd_asic_reg_offset(offset) = 11x"508";
   end function;

   impure function dd_read_half(offset : unsigned(10 downto 0)) return std_logic_vector is
      variable data : std_logic_vector(15 downto 0);
   begin
      data := (others => '0');
      case to_integer(dd_asic_reg_offset(offset)) is
         when 16#500# => data := dd_data;
         when 16#504# => data := (others => '0');
         when 16#508# =>
            -- ares ASIC_STATUS bit layout
            data := '0' & dd_bm_transfer_data & '0' & dd_bm_transfer_c2 &
                    '0' & dd_bm_interrupt & dd_cmd_interrupt_visible & dd_disk_inserted &
                    (dd_cmd_pending or dd_seek_pending) & dd_hard_reset &
                    '0' & dd_spindle_stopped & dd_head_retracted & '0' & '0' & dd_disk_changed;
         when 16#50C# => data := '0' & dd_index_lock & dd_index_lock & std_logic_vector(dd_head_track);
         when 16#510# =>
            -- ares ASIC_BM_STATUS: bit15 BM start latch, bit9 micro error,
            -- bit8 block transfer, bit6/5 C1 double/single.
            data := (others => '0');
            data(15) := dd_bm_running;
            data(9)  := dd_bm_micro_error;
            data(8)  := dd_bm_blocks;
            data(6)  := dd_bm_c1_double;
            data(5)  := dd_bm_c1_single;
         when 16#514# =>
            data := (others => '0');
            data(14) := dd_bm_micro_error;
            data(10) := not dd_disk_inserted;
         when 16#518# => data := (others => '0');
         when 16#51C# =>
            -- ares ASIC_CUR_SECTOR: raw track-absolute sector in the high byte.
            data := std_logic_vector(dd_current_sector) & x"C3";
         when 16#528# => data := x"00" & std_logic_vector(dd_sector_size);
         when 16#52C# | 16#530# => data := std_logic_vector(dd_sectors_in_block) & std_logic_vector(dd_sector_size_full);
         when 16#540# =>
            if (ddDevMode = '1') then data := x"0004";
            else data := x"0003";
            end if;
         when others  => data := (others => '0');
      end case;
      return data;
   end function;

begin 

   irq_out    <= PI_STATUS_irq;
   dd_cmd_interrupt_visible <= dd_cmd_interrupt;
   dd_irq_out <= dd_cmd_interrupt_visible or dd_bm_interrupt;

   rdram_burstcount <= 10x"01";
   ddram_burstcount <= 10x"01";
   sdram_burstcount <= x"01";
   -- A real 64DD attachment always brings the IPL ROM/ASIC together. A disk
   -- image alone is just staged media and must not make expansion-aware carts
   -- see DD hardware until the IPL window has been populated.
   dd_attached <= ddIplAvailable;

   distEndOfRow <= 16#800# - to_integer(PI_DRAM_ADDR(10 downto 0));

   PI_BSD_LAT <= PI_BSD_DOM2_LAT when (PI_CART_ADDR(28 downto 0) < 16#10000000#) else PI_BSD_DOM1_LAT;
   PI_BSD_PWD <= PI_BSD_DOM2_PWD when (PI_CART_ADDR(28 downto 0) < 16#10000000#) else PI_BSD_DOM1_PWD;
   PI_BSD_PGS <= PI_BSD_DOM2_PGS when (PI_CART_ADDR(28 downto 0) < 16#10000000#) else PI_BSD_DOM1_PGS;
   PI_BSD_RLS <= PI_BSD_DOM2_RLS when (PI_CART_ADDR(28 downto 0) < 16#10000000#) else PI_BSD_DOM1_RLS;

   PI_DRAM_pagemask <= 18x"3FFFC" when PI_BSD_PGS = 0  else
                       18x"3FFF8" when PI_BSD_PGS = 1  else
                       18x"3FFF0" when PI_BSD_PGS = 2  else
                       18x"3FFE0" when PI_BSD_PGS = 3  else
                       18x"3FFC0" when PI_BSD_PGS = 4  else
                       18x"3FF80" when PI_BSD_PGS = 5  else
                       18x"3FF00" when PI_BSD_PGS = 6  else
                       18x"3FE00" when PI_BSD_PGS = 7  else
                       18x"3FC00" when PI_BSD_PGS = 8  else
                       18x"3F800" when PI_BSD_PGS = 9  else
                       18x"3F000" when PI_BSD_PGS = 10 else
                       18x"3E000" when PI_BSD_PGS = 11 else
                       18x"3C000" when PI_BSD_PGS = 12 else
                       18x"38000" when PI_BSD_PGS = 13 else
                       18x"30000" when PI_BSD_PGS = 14 else
                       18x"20000";

   process (clk1x)
      variable blocklength_new : integer range 0 to 128;
      variable count_new       : unsigned(24 downto 0);
      variable writemask_new   : std_logic_vector(1 downto 0);
      variable dma_readData    : std_logic_vector(15 downto 0);
      variable dma_fifoData    : std_logic_vector(15 downto 0);
      variable dd_offset       : unsigned(10 downto 0);
      variable dd_wdata        : std_logic_vector(15 downto 0);
      variable dd_writeData    : std_logic_vector(15 downto 0);
      variable dd_directData32 : std_logic_vector(31 downto 0);
      variable dd_next_sector  : unsigned(7 downto 0);
      variable dd_block_sel    : std_logic;
      variable dd_start_sector : unsigned(7 downto 0);
      variable dd_req_user     : std_logic;
      variable dd_req_stop     : std_logic;
      variable rtc_second      : integer range 0 to 255;
      variable rtc_minute      : integer range 0 to 255;
      variable rtc_hour        : integer range 0 to 255;
      variable rtc_day         : integer range 0 to 255;
      variable rtc_month       : integer range 0 to 255;
      variable rtc_year        : integer range 0 to 255;
      variable rtc_month_days  : integer range 28 to 31;
      variable rtc_seed_applied: boolean;

   begin
      if rising_edge(clk1x) then
      
         error_PI     <= '0';
         change_sram  <= '0';
         change_flash <= '0';
         flash_wrenA  <= '0';
         PIfifo_Wr    <= '0';
         dd_sector_wren_a <= '0';
         dd_sector_wren_b <= (others => '0');
         rtc_seed_applied := false;
         
         if (PI_STATUS_DMAbusy = '1') then
            rom_slow_cnt <= rom_slow_cnt + 1;
         end if;
      
         if (reset = '1') then
            
            bus_reg_done            <= '0';

            PI_DRAM_ADDR            <= (others => '0');
            PI_CART_ADDR            <= (others => '0');
            PI_LEN                  <= (others => '0');
            PI_WR_LEN               <= (others => '0');
            PI_STATUS_DMAbusy       <= ss_in(0)(56); -- '0';
            PI_STATUS_IObusy        <= ss_in(0)(57); -- '0';
            PI_STATUS_DMAerror      <= ss_in(0)(58); -- '0';
            PI_STATUS_irq           <= ss_in(0)(59); -- '0';
            PI_BSD_DOM1_LAT         <= unsigned(ss_in(2)(7 downto 0));   --(others => '0');
            PI_BSD_DOM1_PWD         <= unsigned(ss_in(2)(15 downto 8));  --(others => '0');
            PI_BSD_DOM1_PGS         <= unsigned(ss_in(2)(19 downto 16)); --(others => '0');
            PI_BSD_DOM1_RLS         <= unsigned(ss_in(2)(21 downto 20)); --(others => '0');
            PI_BSD_DOM2_LAT         <= unsigned(ss_in(2)(29 downto 22)); --(others => '0');
            PI_BSD_DOM2_PWD         <= unsigned(ss_in(2)(37 downto 30)); --(others => '0');
            PI_BSD_DOM2_PGS         <= unsigned(ss_in(2)(41 downto 38)); --(others => '0');
            PI_BSD_DOM2_RLS         <= unsigned(ss_in(2)(43 downto 42)); --(others => '0');
               
            state                   <= IDLE;

            bus_cart_read_latched   <= '0';
            bus_cart_write_latched  <= '0';
            dma_is_ipl              <= '0';
            dd_ipl_rd_half          <= '0';
            ddram_rnw               <= '1';
            ddram_writeMask         <= (others => '0');
            ddram_dataWrite         <= (others => '0');
            
            flashState              <= FLASHIDLE;
            flash_statusword        <= (others => '0');
            flash_offset            <= (others => '0');

            dd_hard_reset           <= '1';
            dd_disk_inserted        <= ddDiskAvailable;
            dd_disk_changed         <= ddDiskAvailable;
            dd_disk_available_d     <= ddDiskAvailable;
            dd_head_retracted       <= '1';
            dd_spindle_stopped      <= '1';
            dd_motor_started        <= '0';
            dd_index_lock           <= '0';
            dd_data                 <= (others => '0');
            dd_rtc_year_month       <= x"9601";
            dd_rtc_day_hour         <= x"0100";
            dd_rtc_minute_second    <= x"0000";
            dd_rtc_seeded           <= '0';
            dd_cmd_pending          <= '0';
            dd_cmd_interrupt        <= '0';
            dd_bm_interrupt         <= '0';
            dd_bm_transfer_data     <= '0';
            dd_bm_transfer_c2       <= '0';
            dd_bm_micro_error       <= '0';
            dd_bm_c1_single         <= '0';
            dd_bm_c1_double         <= '0';
            dd_bm_running           <= '0';
            dd_bm_read_mode         <= '0';
            dd_bm_blocks            <= '0';
            dd_bm_reset_latched     <= '0';
            dd_bm_stop_reason       <= (others => '0');
            dd_current_sector       <= (others => '0');
            dd_sector_advance_pending <= '0';
            dd_sector_advance_counter <= (others => '0');
            dd_sector_size          <= x"E7";
            dd_sector_size_full     <= x"E7";
            dd_sectors_in_block     <= x"59";
            dd_head_track           <= (others => '0');
            dd_seek_pending         <= '0';
            dd_seek_counter         <= (others => '0');
            dd_seek_target          <= (others => '0');
            dd_load_addr            <= (others => '0');
            dd_load_count           <= 0;
            dd_load_total           <= 0;
            dd_store_addr           <= (others => '0');
            dd_store_count          <= 0;
            dd_store_next_sector    <= (others => '0');
            dd_store_set_data       <= '0';
            dd_store_stop           <= '0';
            dd_write_sector_ready   <= '0';
            dd_dirty_addr           <= (others => '0');
 
         elsif (ce = '1') then
         
            bus_reg_done     <= '0';
            bus_reg_dataRead <= (others => '0');

               dd_disk_inserted    <= ddDiskAvailable;
               if (ddDiskAvailable = '1' and dd_disk_available_d = '0') then
                  -- SummerCart INSERTED state does not assert DISK_CHANGED.
                  -- Keep the reset-time flag for media present at power-on, but
                  -- present a newly inserted disk cleanly to an already-running IPL.
                  dd_disk_changed       <= '0';
                  dd_motor_started      <= '0';
                  dd_bm_interrupt       <= '0';
               dd_bm_transfer_data   <= '0';
               dd_bm_transfer_c2     <= '0';
               dd_bm_micro_error     <= '0';
               dd_bm_c1_single       <= '0';
               dd_bm_c1_double       <= '0';
               dd_bm_running         <= '0';
               dd_bm_read_mode       <= '0';
               dd_bm_blocks          <= '0';
               dd_bm_reset_latched   <= '0';
               dd_bm_stop_reason     <= x"1";
               dd_sector_advance_pending <= '0';
               dd_sector_advance_counter <= (others => '0');
               dd_write_sector_ready <= '0';
            end if;
            dd_disk_available_d <= ddDiskAvailable;
            if (ddDiskAvailable = '0') then
               dd_disk_changed <= '0';
               dd_motor_started <= '0';
               dd_write_sector_ready <= '0';
            end if;

            if (dd_rtc_seeded = '0') then
               if (dd_is_bcd(hpsRTC( 7 downto  0)) and
                   dd_is_bcd(hpsRTC(15 downto  8)) and
                   dd_is_bcd(hpsRTC(23 downto 16)) and
                   dd_is_bcd(hpsRTC(31 downto 24)) and
                   dd_is_bcd(hpsRTC(39 downto 32)) and
                   dd_is_bcd(hpsRTC(47 downto 40))) then
                  rtc_second := dd_bcd_to_int(hpsRTC( 7 downto  0));
                  rtc_minute := dd_bcd_to_int(hpsRTC(15 downto  8));
                  rtc_hour   := dd_bcd_to_int(hpsRTC(23 downto 16));
                  rtc_day    := dd_bcd_to_int(hpsRTC(31 downto 24));
                  rtc_month  := dd_bcd_to_int(hpsRTC(39 downto 32));
                  rtc_year   := dd_bcd_to_int(hpsRTC(47 downto 40));
                  if (rtc_second < 60 and rtc_minute < 60 and rtc_hour < 24 and
                      rtc_month >= 1 and rtc_month <= 12) then
                     rtc_month_days := dd_days_in_month(rtc_year, rtc_month);
                     if (rtc_day >= 1 and rtc_day <= rtc_month_days) then
                        dd_rtc_minute_second <= hpsRTC(15 downto 8) & hpsRTC(7 downto 0);
                        dd_rtc_day_hour      <= hpsRTC(31 downto 24) & hpsRTC(23 downto 16);
                        dd_rtc_year_month    <= hpsRTC(47 downto 40) & hpsRTC(39 downto 32);
                        dd_rtc_seeded        <= '1';
                        rtc_seed_applied     := true;
                     end if;
                  end if;
               end if;
            end if;

            if (second_ena = '1' and not rtc_seed_applied) then
               rtc_second := dd_bcd_to_int(dd_rtc_minute_second(7 downto 0));
               rtc_minute := dd_bcd_to_int(dd_rtc_minute_second(15 downto 8));
               rtc_hour   := dd_bcd_to_int(dd_rtc_day_hour(7 downto 0));
               rtc_day    := dd_bcd_to_int(dd_rtc_day_hour(15 downto 8));
               rtc_month  := dd_bcd_to_int(dd_rtc_year_month(7 downto 0));
               rtc_year   := dd_bcd_to_int(dd_rtc_year_month(15 downto 8));

               if (rtc_month < 1 or rtc_month > 12) then rtc_month := 1; end if;
               rtc_month_days := dd_days_in_month(rtc_year, rtc_month);
               if (rtc_day < 1 or rtc_day > rtc_month_days) then rtc_day := 1; end if;

               rtc_second := rtc_second + 1;
               if (rtc_second >= 60) then
                  rtc_second := 0;
                  rtc_minute := rtc_minute + 1;
                  if (rtc_minute >= 60) then
                     rtc_minute := 0;
                     rtc_hour := rtc_hour + 1;
                     if (rtc_hour >= 24) then
                        rtc_hour := 0;
                        rtc_day := rtc_day + 1;
                        if (rtc_day > rtc_month_days) then
                           rtc_day := 1;
                           rtc_month := rtc_month + 1;
                           if (rtc_month > 12) then
                              rtc_month := 1;
                              rtc_year := rtc_year + 1;
                              if (rtc_year >= 100) then
                                 rtc_year := 0;
                              end if;
                           end if;
                        end if;
                     end if;
                  end if;
               end if;

               dd_rtc_minute_second <= dd_int_to_bcd(rtc_minute) & dd_int_to_bcd(rtc_second);
               dd_rtc_day_hour      <= dd_int_to_bcd(rtc_day) & dd_int_to_bcd(rtc_hour);
               dd_rtc_year_month    <= dd_int_to_bcd(rtc_year) & dd_int_to_bcd(rtc_month);
            end if;

            if (dd_seek_pending = '1') then
               if (dd_seek_counter = 0) then
                  dd_seek_pending    <= '0';
                  dd_head_track      <= dd_seek_target;
                  dd_index_lock      <= '1';
                  dd_cmd_pending     <= '0';
                  dd_cmd_interrupt   <= '1';
                  dd_head_retracted  <= '0';
                  dd_spindle_stopped <= '0';
               else
                  dd_seek_counter <= dd_seek_counter - 1;
               end if;
            end if;

            if (dd_sector_advance_pending = '1' and dd_sector_advance_counter /= 0) then
               dd_sector_advance_counter <= dd_sector_advance_counter - 1;
            end if;

            -- bus regs read
            if (bus_reg_read = '1') then
               bus_reg_done <= '1';
               case (bus_reg_addr(19 downto 2) & "00") is
                  when x"00000" =>
                     bus_reg_dataRead(23 downto 0) <= std_logic_vector(PI_DRAM_ADDR);
                  when x"00004" =>
                     bus_reg_dataRead(31 downto 0) <= std_logic_vector(PI_CART_ADDR);
                  when x"00008" =>
                     bus_reg_dataRead( 6 downto 0) <= (others => '1'); -- maybe different for reads < 8?
                  when x"0000C" =>
                     bus_reg_dataRead( 6 downto 0) <= std_logic_vector(PI_WR_LEN);
                  when x"00010" => 
                     bus_reg_dataRead(0) <= PI_STATUS_DMAbusy;    
                     bus_reg_dataRead(1) <= PI_STATUS_IObusy;    
                     bus_reg_dataRead(2) <= PI_STATUS_DMAerror;    
                     bus_reg_dataRead(3) <= PI_STATUS_irq;
                  when x"00014" =>
                     bus_reg_dataRead(7 downto 0) <= std_logic_vector(PI_BSD_DOM1_LAT);
                  when x"00018" =>
                     bus_reg_dataRead(7 downto 0) <= std_logic_vector(PI_BSD_DOM1_PWD);
                  when x"0001C" =>
                     bus_reg_dataRead(3 downto 0) <= std_logic_vector(PI_BSD_DOM1_PGS);
                  when x"00020" =>
                     bus_reg_dataRead(1 downto 0) <= std_logic_vector(PI_BSD_DOM1_RLS);
                  when x"00024" =>
                     bus_reg_dataRead(7 downto 0) <= std_logic_vector(PI_BSD_DOM2_LAT);
                  when x"00028" =>
                     bus_reg_dataRead(7 downto 0) <= std_logic_vector(PI_BSD_DOM2_PWD);
                  when x"0002C" =>
                     bus_reg_dataRead(3 downto 0) <= std_logic_vector(PI_BSD_DOM2_PGS);
                  when x"00030" =>
                     bus_reg_dataRead(1 downto 0) <= std_logic_vector(PI_BSD_DOM2_RLS);
                  when others =>
               end case;
            end if;

            -- bus regs write
            if (bus_reg_write = '1') then
               bus_reg_done <= '1';
               
               if ((bus_reg_addr(19 downto 2) & "00") = x"00010") then
                  if (bus_reg_dataWrite(1) = '1') then
                     PI_STATUS_irq <= '0';
                  end if;
                  if (bus_reg_dataWrite(0) = '1') then
                     PI_STATUS_DMAbusy  <= '0';
                     PI_STATUS_DMAerror <= '0';
                  end if;
                  
               --elsif (PI_STATUS_DMAbusy = '1' or PI_STATUS_IObusy = '1') then -- also check IObusy?
               elsif (PI_STATUS_DMAbusy = '1') then
                  PI_STATUS_DMAerror <= '1';
                  error_PI           <= '1';
               
               else
               
                  case (bus_reg_addr(19 downto 2) & "00") is
                     when x"00000" => PI_DRAM_ADDR <= unsigned(bus_reg_dataWrite(23 downto 1)) & '0';   
                     when x"00004" => PI_CART_ADDR <= unsigned(bus_reg_dataWrite(31 downto 1)) & '0';
                     
                     when x"00008" | x"0000C" => 
                        PI_STATUS_DMAbusy <= '1';
                        first128          <= '1';
                        PI_LEN            <= resize(unsigned(bus_reg_dataWrite(23 downto 0)), 25) + to_unsigned(1, 25);      
                        MaxBlockSize      <= 128;
                        PI_DRAM_valid     <= '0';
                        rom_slow_cnt      <= (others => '0');
                        rom_slow_sum      <= (others => '0');
                        if ((dd_attached = '1') and dd_reg_selected(PI_CART_ADDR(28 downto 0))) then
                        else
                        end if;
                        if (bus_reg_addr(19 downto 2) & "00" = x"00008") then dmaIsWrite <= '0'; else dmaIsWrite <= '1'; end if;
                        
                     when x"00010" => null; --handled above
                     when x"00014" => PI_BSD_DOM1_LAT <= unsigned(bus_reg_dataWrite(7 downto 0));    
                     when x"00018" => PI_BSD_DOM1_PWD <= unsigned(bus_reg_dataWrite(7 downto 0));    
                     when x"0001C" => PI_BSD_DOM1_PGS <= unsigned(bus_reg_dataWrite(3 downto 0));    
                     when x"00020" => PI_BSD_DOM1_RLS <= unsigned(bus_reg_dataWrite(1 downto 0));    
                     when x"00024" => PI_BSD_DOM2_LAT <= unsigned(bus_reg_dataWrite(7 downto 0));    
                     when x"00028" => PI_BSD_DOM2_PWD <= unsigned(bus_reg_dataWrite(7 downto 0));    
                     when x"0002C" => PI_BSD_DOM2_PGS <= unsigned(bus_reg_dataWrite(3 downto 0));    
                     when x"00030" => PI_BSD_DOM2_RLS <= unsigned(bus_reg_dataWrite(1 downto 0));
                     when others   => null;
                  end case;
                  
               end if;
            end if;
            
            
            -- PI state machine
            bus_cart_done     <= '0';
            bus_cart_dataRead <= (others => '0');
            sdram_request     <= '0';
            rdram_request     <= '0';
            ddram_request     <= '0';
            ddram_rnw         <= '1';
            ddram_writeMask   <= (others => '0');
            
            if (writtenTime > 0) then
               writtenTime <= writtenTime - 1;
            else
               PI_STATUS_IObusy <= '0';
            end if;
            
            if (bus_cart_read = '1') then
               bus_cart_read_latched <= '1';
            end if;            
            if (bus_cart_write = '1') then
               bus_cart_write_latched <= '1';
            end if;

            case (state) is
            
               when IDLE =>
               
                  flash_addrB  <= (others => '0');
                  
                  -- ares bmRequest: the single buffer-manager service point. Armed by
                  -- BM start writes (50k delay) and ASIC_STATUS interrupt ACKs (38k delay).
                  -- SummerCart's MCU does not consume a write buffer until the N64
                  -- touches its terminal halfword. Keep an expired ares-style timer
                  -- pending until that transfer-complete indication is observed.
                  if (dd_sector_advance_pending = '1' and dd_sector_advance_counter = 0 and
                      (dd_bm_running = '0' or dd_bm_read_mode = '1' or
                       dd_current_sector = 0 or dd_current_sector = DD_SECTOR_BLOCK_BASE or
                       dd_write_sector_ready = '1')) then
                     dd_sector_advance_pending <= '0';
                     if (dd_bm_running = '0') then
                        dd_bm_interrupt <= '0';
                     else
                        -- per-request status reset, as at the top of ares' bmRequest
                        dd_bm_transfer_data <= '0';
                        dd_bm_transfer_c2   <= '0';
                        dd_bm_micro_error   <= '0';
                        dd_bm_c1_single     <= '0';
                        dd_bm_c1_double     <= '0';
                        dd_block_sel    := '0';
                        dd_start_sector := dd_current_sector;
                        if (dd_current_sector >= DD_SECTOR_BLOCK_BASE) then
                           dd_block_sel    := '1';
                           dd_start_sector := dd_current_sector - DD_SECTOR_BLOCK_BASE;
                        end if;
                        if (dd_bm_read_mode = '1') then
                           if (dd_start_sector < DD_SECTOR_USER_END) then
                              -- user sector: fill the buffer, then DD_LOAD_WAIT raises the
                              -- BM interrupt with requestUserSector and advances the sector
                              dd_load_addr  <= dd_sector_ddr_address(dd_head_track, dd_block_sel, dd_start_sector);
                              dd_load_count <= 0;
                              dd_load_total <= 32;
                              state         <= DD_LOAD_REQ;
                           elsif (dd_start_sector < DD_SECTOR_C2_LAST) then
                              -- silent C2 sector: interrupt only
                              dd_current_sector <= dd_current_sector + 1;
                              dd_bm_interrupt   <= '1';
                           elsif (dd_start_sector = DD_SECTOR_C2_LAST) then
                              -- last C2 sector: request C2, then wrap or stop
                              dd_bm_transfer_c2 <= '1';
                              if (dd_bm_blocks = '1') then
                                 dd_bm_blocks <= '0';
                                 if (dd_block_sel = '1') then
                                    dd_current_sector <= (others => '0');
                                 else
                                    dd_current_sector <= DD_SECTOR_BLOCK_BASE;
                                 end if;
                              else
                                 dd_bm_running     <= '0';
                                 dd_bm_stop_reason <= x"7";
                              end if;
                              dd_bm_interrupt <= '1';
                           else
                              dd_bm_interrupt <= '1';
                           end if;
                        else
                           -- ares write mode: store the previous sector, then request the next
                           dd_req_user := '0';
                           dd_req_stop := '0';
                           dd_next_sector := dd_current_sector + 1;
                           if (dd_start_sector <= DD_SECTOR_USER_END) then
                              dd_req_user := '1';
                           end if;
                           if (dd_start_sector >= DD_SECTOR_USER_END) then
                              if (dd_bm_blocks = '1') then
                                 dd_bm_blocks <= '0';
                                 if (dd_block_sel = '1') then
                                    dd_next_sector := to_unsigned(1, 8);
                                 else
                                    dd_next_sector := DD_SECTOR_BLOCK_BASE + 1;
                                 end if;
                              else
                                 dd_req_user := '0';
                                 dd_req_stop := '1';
                              end if;
                           end if;
                           if (dd_start_sector > 0 and dd_start_sector <= DD_SECTOR_USER_END and
                               ddDiskAvailable = '1') then
                              dd_write_sector_ready <= '0';
                              dd_store_addr        <= dd_sector_ddr_address(dd_head_track, dd_block_sel, dd_start_sector - 1);
                              dd_dirty_addr        <= dd_sector_ddr_address(dd_head_track, dd_block_sel, to_unsigned(0, 8)) + DD_DIRTY_FLAG_OFFSET;
                              dd_store_count       <= 0;
                              dd_store_next_sector <= dd_next_sector;
                              dd_store_set_data    <= dd_req_user;
                              dd_store_stop        <= dd_req_stop;
                              state                <= DD_STORE_READ;
                           else
                              dd_bm_transfer_data <= dd_req_user;
                              if (dd_req_stop = '1') then
                                 dd_bm_running     <= '0';
                                 dd_bm_stop_reason <= x"5";
                              end if;
                              dd_current_sector <= dd_next_sector;
                              dd_bm_interrupt   <= '1';
                           end if;
                        end if;
                     end if;
                  elsif (bus_cart_read_latched = '1') then
                     bus_cart_read_latched <= '0';
                     bus_cart_dataRead     <= std_logic_vector(bus_cart_addr(15 downto 0)) & std_logic_vector(bus_cart_addr(15 downto 0)); -- open bus is default
                     
                     if ((dd_attached = '1') and dd_reg_selected(bus_cart_addr(28 downto 0))) then -- DD registers
                        dd_offset         := bus_cart_addr(10 downto 0);
                        if (dd_offset >= 11x"400" and dd_offset < 11x"500") then
                           dd_reg_read_offset <= dd_offset;
                           dd_sector_addr_b   <= std_logic_vector(dd_offset(7 downto 3));
                           state              <= DD_REG_READ;
                        else
                            dma_readData        := dd_read_half(dd_offset);
                            bus_cart_dataRead   <= dma_readData & dd_read_half(dd_offset + 2);
                             bus_cart_done     <= '1';

                             if (dd_is_cmd_status_offset(dd_offset)) then
                                -- ares: a status read that observes the BM interrupt ACKs it
                                -- and schedules the next buffer-manager request.
                                if (dd_bm_interrupt = '1') then
                                   dd_bm_interrupt <= '0';
                                   dd_sector_advance_pending <= '1';
                                   dd_sector_advance_counter <= DD_BM_NEXT_DELAY_CLK1X;
                                end if;
                            end if;
                         end if;
                     elsif (dd_ipl_selected(bus_cart_addr(28 downto 0)) and ddIplAvailable = '1') then -- DD IPL ROM
                        -- Serve the IPL aperture from the dedicated DDR copy, not the
                        -- SDRAM ROM fastload area (which holds the cartridge ROM in
                        -- cart expansion mode).
                        ddram_request   <= '1';
                        ddram_rnw       <= '1';
                        ddram_address   <= DD_IPL_DDR_BASE + (6x"0" & bus_cart_addr(21 downto 3) & "000");
                        dd_ipl_rd_half  <= bus_cart_addr(2);
                        state           <= DD_IPL_RD_WAIT;
                     elsif (bus_cart_addr(28 downto 0) < 16#08000000#) then
                        bus_cart_done <= '1';
                     elsif (bus_cart_addr(28 downto 0) < 16#10000000#) then -- SRAM+FLASH                          
                        if (SAVETYPE = "011" or SAVETYPE = "100") then
                           state         <= READSRAM;
                           sdram_request <= '1';
                           sdram_rnw     <= '1';
                           if (SAVETYPE = "011") then
                              sdram_address <= (11x"0" & bus_cart_addr(14 downto 2) & "00") + to_unsigned(16#400000#, 27);
                           else
                              sdram_address <= (9x"0" &  bus_cart_addr(16 downto 2) & "00") + to_unsigned(16#400000#, 27);
                           end if;
                        elsif (SAVETYPE = "101") then
                           bus_cart_done     <= '1';
                           if (bus_cart_addr(2) = '0') then
                              bus_cart_dataRead <= flash_statusword(63 downto 32);
                           else
                              bus_cart_dataRead <= flash_statusword(31 downto 0);
                           end if;
                        else 
                           bus_cart_done <= '1';
                        end if;
                     elsif (bus_cart_addr(28 downto 0) < (16#10000000# + to_integer(cartSize)) and cartAvailable = '1') then -- game rom
                        if (PI_STATUS_IObusy = '1') then
                           PI_STATUS_IObusy  <= '0';
                           bus_cart_dataRead <= writtenData;
                           bus_cart_done     <= '1';
                        else
                           state         <= READROM;
                           sdram_request <= '1';
                           sdram_rnw     <= '1';
                           if (bus_cart_addr(1) = '1') then
                              sdram_address <= (bus_cart_addr(25 downto 2) & "10") + to_unsigned(16#1000004#, 27);
                           else
                              sdram_address <= (bus_cart_addr(25 downto 2) & "00") + to_unsigned(16#1000000#, 27);
                           end if;
                        end if;
                     else
                        bus_cart_done <= '1';
                     end if;
                     
                  elsif (bus_cart_write_latched = '1') then
                  
                     bus_cart_write_latched <= '0';
                  
                     if (PI_STATUS_IObusy = '0') then 
                        PI_STATUS_IObusy  <= '1';
                        writtenData       <= bus_cart_dataWrite;
                        if (fastDecay = '1') then
                           writtenTime       <= 1;
                        else
                           writtenTime       <= 150;
                        end if;
                     end if;

                     if ((dd_attached = '1') and dd_reg_selected(bus_cart_addr(28 downto 0))) then -- DD registers
                        dd_offset     := bus_cart_addr(10 downto 0);
                        bus_cart_done <= '1';

                        if (dd_offset >= 11x"400" and dd_offset < 11x"500") then
                           dd_sector_addr_b     <= std_logic_vector(dd_offset(7 downto 3));
                           dd_sector_data_in_b0 <= byteswap16(bus_cart_dataWrite(31 downto 16));
                           dd_sector_data_in_b1 <= byteswap16(bus_cart_dataWrite(15 downto 0));
                           dd_sector_data_in_b2 <= byteswap16(bus_cart_dataWrite(31 downto 16));
                           dd_sector_data_in_b3 <= byteswap16(bus_cart_dataWrite(15 downto 0));
                           if (dd_offset(2) = '0') then
                              dd_sector_wren_b(1 downto 0) <= "11";
                           else
                              dd_sector_wren_b(3 downto 2) <= "11";
                           end if;
                           if dd_offset(7 downto 2) = dd_sector_size(7 downto 2) then
                              dd_write_sector_ready <= '1';
                           end if;
                        else
                           dd_wdata := bus_cart_dataWrite(31 downto 16);
                           case to_integer(dd_asic_reg_offset(dd_offset)) is
                                 when 16#500# =>
                                    dd_data <= dd_wdata;

                              when 16#504# =>
                                 null;

                             when 16#508# =>
                                 dd_cmd_pending   <= '0';
                                 dd_cmd_interrupt <= '1';
                                 case dd_wdata(7 downto 0) is
                                    when x"01" | x"02" =>
                                       dd_seek_pending    <= '1';
                                       dd_seek_target     <= unsigned(dd_data(12 downto 0));
                                       dd_cmd_pending     <= '1';
                                       dd_cmd_interrupt   <= '0';
                                       dd_index_lock      <= '0';
                                       dd_head_retracted  <= '0';
                                       dd_spindle_stopped <= '0';
                                       if (dd_motor_started = '0') then
                                          dd_motor_started <= '1';
                                          dd_seek_counter <= DD_SEEK_SPINUP_DELAY_CLK1X;
                                       else
                                          dd_seek_counter <= DD_SEEK_DELAY_CLK1X;
                                       end if;
                                    when x"03" | x"05" =>
                                       dd_seek_pending    <= '0';
                                       dd_head_track      <= (others => '0');
                                       dd_index_lock      <= '1';
                                       dd_head_retracted  <= '0';
                                       dd_spindle_stopped <= '0';
                                    when x"04" =>
                                       dd_seek_pending    <= '0';
                                       dd_head_retracted  <= '1';
                                       dd_spindle_stopped <= '1';
                                       dd_motor_started   <= '0';
                                    when x"08" =>
                                       dd_disk_changed <= '0';
                                    when x"09" =>
                                       dd_seek_pending <= '0';
                                       dd_hard_reset   <= '0';
                                       dd_disk_changed <= '0';
                                    when x"0A" =>
                                       dd_data <= x"0114";
                                    when x"0B" =>
                                       null;
                                    when x"0C" =>
                                       dd_data <= (others => '0');
                                    when x"00" | x"06" | x"07" | x"15" =>
                                       null;
                                    when x"0D" =>
                                       dd_head_retracted  <= '1';
                                       dd_spindle_stopped <= '0';
                                    when x"0E" =>
                                       dd_index_lock <= '1';
                                    when x"1B" =>
                                       dd_data <= x"0000";
                                    when x"0F" =>
                                       dd_rtc_year_month <= dd_data;
                                       dd_rtc_seeded <= '1';
                                    when x"10" =>
                                       dd_rtc_day_hour <= dd_data;
                                       dd_rtc_seeded <= '1';
                                    when x"11" =>
                                       dd_rtc_minute_second <= dd_data;
                                       dd_rtc_seeded <= '1';
                                    when x"12" =>
                                       dd_data <= dd_rtc_year_month;
                                    when x"13" =>
                                       dd_data <= dd_rtc_day_hour;
                                    when x"14" =>
                                       dd_data <= dd_rtc_minute_second;
                                    when others =>
                                       null;
                                 end case;

                              when 16#510# =>
                                 -- ares ASIC_BM_CTL: every write latches the sector number, read
                                 -- mode and block-transfer; bit 8 ACKs the mecha interrupt; bit 12
                                 -- arms the BM reset latch and the next write without bit 12
                                 -- completes the reset; bit 15 starts the buffer manager.
                                 dd_current_sector <= unsigned(dd_wdata(7 downto 0));
                                 dd_bm_read_mode   <= dd_wdata(14);
                                 dd_bm_blocks      <= dd_wdata(9);
                                 if (dd_wdata(8) = '1') then
                                    dd_cmd_interrupt <= '0';
                                 end if;
                                 if (dd_wdata(12) = '1') then
                                    dd_bm_reset_latched <= '1';
                                 elsif (dd_bm_reset_latched = '1') then
                                    dd_bm_reset_latched <= '0';
                                    dd_bm_running       <= '0';
                                    dd_bm_stop_reason   <= x"2";
                                    dd_bm_interrupt     <= '0';
                                    dd_bm_transfer_data <= '0';
                                    dd_bm_transfer_c2   <= '0';
                                    dd_bm_micro_error   <= '0';
                                    dd_sector_advance_pending <= '0';
                                    dd_sector_advance_counter <= (others => '0');
                                    dd_write_sector_ready <= '0';
                                 end if;
                                 if (dd_wdata(15) = '1') then
                                    if (ddDiskAvailable = '1') then
                                       dd_bm_running     <= '1';
                                       dd_bm_stop_reason <= (others => '0');
                                       dd_write_sector_ready <= '0';
                                       dd_sector_advance_pending <= '1';
                                       dd_sector_advance_counter <= DD_BM_START_DELAY_CLK1X;
                                    else
                                       dd_bm_micro_error      <= '1';
                                       dd_bm_interrupt        <= '1';
                                    end if;
                                 end if;

                              when 16#518# =>
                                 null;

                              when 16#520# =>
                                 if (dd_wdata = x"AAAA") then
                                    dd_hard_reset       <= '1';
                                    dd_disk_changed     <= '0';
                                    dd_head_retracted   <= '1';
                                    dd_spindle_stopped  <= '1';
                                    dd_motor_started    <= '0';
                                    dd_seek_pending     <= '0';
                                    dd_cmd_pending      <= '0';
                                    dd_cmd_interrupt    <= '0';
                                    dd_bm_reset_latched <= '0';
                                    dd_bm_running       <= '0';
                                    dd_bm_read_mode     <= '0';
                                    dd_bm_blocks        <= '0';
                                    dd_bm_stop_reason   <= x"3";
                                    dd_bm_interrupt     <= '0';
                                    dd_bm_transfer_data <= '0';
                                    dd_bm_transfer_c2   <= '0';
                                    dd_bm_c1_single     <= '0';
                                    dd_bm_c1_double     <= '0';
                                    dd_sector_advance_pending <= '0';
                                    dd_sector_advance_counter <= (others => '0');
                                    dd_write_sector_ready <= '0';
                                 end if;

                              when 16#528# =>
                                 dd_sector_size <= unsigned(dd_wdata(7 downto 0));

                              when 16#52C# | 16#530# =>
                                 dd_sector_size_full <= unsigned(dd_wdata(7 downto 0));
                                 dd_sectors_in_block <= unsigned(dd_wdata(15 downto 8));

                              when others =>
                                 null;
                           end case;
                        end if;
                     elsif (bus_cart_addr(28 downto 0) < 16#08000000#) then
                        bus_cart_done <= '1';
                     elsif (bus_cart_addr(28 downto 0) < 16#10000000#) then -- SRAM+FLASH  
                        if (SAVETYPE = "011" or SAVETYPE = "100") then
                           change_sram      <= '1';
                           state            <= WRITESRAM;
                           sdram_request    <= '1';
                           sdram_rnw        <= '0';
                           sdram_dataWrite  <= byteswap32(bus_cart_dataWrite);
                           sdram_writeMask  <= "1111";
                           if (SAVETYPE = "011") then
                              sdram_address <= (11x"0" & bus_cart_addr(14 downto 2) & "00") + to_unsigned(16#400000#, 27);
                           else
                              sdram_address <= (9x"0" &  bus_cart_addr(16 downto 2) & "00") + to_unsigned(16#400000#, 27);
                           end if;
                        elsif (SAVETYPE = "101") then
                           bus_cart_done <= '1';
                           if (bus_cart_addr(26 downto 0) /= 0) then
                              case (bus_cart_dataWrite(31 downto 24)) is
                                 when x"4B" => -- set erase offset
                                    flash_offset <= unsigned(bus_cart_dataWrite(9 downto 0));
                                 
                                 when x"78" => -- erase
                                    flashState        <= FLASHERASE;
                                    flash_statusword  <= x"1111800800C2001D";
                                 
                                 when x"A5" => -- set write offset
                                    flash_offset <= unsigned(bus_cart_dataWrite(9 downto 0));
                                    flash_statusword  <= x"1111800400C2001D";
                                 
                                 when x"B4" => -- write
                                    flashState        <= FLASHWRITE;
                                 
                                 when x"D2" => -- execute
                                    if (flashState = FLASHERASE or flashState = FLASHWRITE) then
                                       bus_cart_done     <= '0';
                                       state             <= WRITEFLASH;
                                    end if;
                                 
                                 when x"E1" => -- status
                                    flashState        <= FLASHSTATUS;
                                    flash_statusword  <= x"1111800100C2001D";
                                 
                                 when x"F0" => -- read
                                    flashState        <= FLASHREAD;
                                    flash_statusword  <= x"11118004F000001D";
                                    
                                 when others => null;
                              end case;
                           end if;
                        else
                           bus_cart_done <= '1';
                        end if;
                     else
                        bus_cart_done <= '1';
                     end if;
                     
                  elsif (PI_STATUS_DMAbusy = '1') then
                     
                     if (PI_LEN > 0) then
                     
                        if (dmaIsWrite = '1') then
                        
                           state <= COPYDMABLOCK;
                           
                           blocklength_new := MaxBlockSize - to_integer(PI_DRAM_ADDR(2 downto 0));
                           if (distEndOfRow < blocklength_new) then
                              blocklength_new := distEndOfRow;
                           end if;
                           if (PI_LEN < blocklength_new) then
                              blocklength_new := to_integer(PI_LEN);
                           end if;
                           
                           maxram           <= blocklength_new - to_integer(PI_DRAM_ADDR(2 downto 0));
                           blocklength      <= blocklength_new;
                           copycnt          <= 0;
                           distEndOfRowSave <= distEndOfRow;
                           misAlignSave     <= to_integer(PI_DRAM_ADDR(2 downto 0));
                           rom_slow_sum     <= rom_slow_sum + 28;
                           
                        else 
                        
                           state <= DMA_READRDRAM;
                           
                           blocklength_new := 128;
                           if (PI_LEN < 128) then
                              blocklength_new := to_integer(PI_LEN);
                           end if;
                           count_new := PI_LEN - blocklength_new;
                           if (count_new(0) = '1') then 
                              count_new := count_new + 1;
                           end if;
                              
                           maxram       <= blocklength_new;
                           blocklength  <= blocklength_new;
                           PI_LEN       <= count_new;
                           copycnt      <= 0;
                           
                        end if;
                           
                     elsif (PIfifo_empty = '1' and (FASTROM = '1' or (rom_slow_cnt >= rom_slow_sum))) then
                        --if (rom_slow_cnt > (rom_slow_sum + 5)) then
                        --   error_PI           <= '1';
                        --end if;
                        PI_STATUS_irq     <= '1';
                        PI_STATUS_DMAbusy <= '0';
                     end if;
                     
                  end if;
            
               when DD_REG_READ =>
                  state <= DD_REG_READ_WAIT;

               when DD_REG_READ_WAIT =>
                  state         <= IDLE;
                  bus_cart_done <= '1';
                  dd_directData32 := (others => '0');
                  if (dd_reg_read_offset(1) = '0') then
                     if (dd_reg_read_offset(2) = '0') then
                        dd_directData32 := byteswap16(dd_sector_data_out_b0) & byteswap16(dd_sector_data_out_b1);
                     else
                        dd_directData32 := byteswap16(dd_sector_data_out_b2) & byteswap16(dd_sector_data_out_b3);
                     end if;
                  else
                     if (dd_reg_read_offset(2) = '0') then
                        dd_directData32 := byteswap16(dd_sector_data_out_b1) & byteswap16(dd_sector_data_out_b2);
                     else
                        dd_directData32 := byteswap16(dd_sector_data_out_b3) & x"0000";
                     end if;
                  end if;
                  bus_cart_dataRead <= dd_directData32;

               -- Direct CPU read of the IPL aperture from the DDR copy. The IPL is
               -- raw big-endian ROM, so the selected 32-bit half is byteswapped to
               -- big-endian exactly like the SDRAM cartridge ROM path (READROM).
               when DD_IPL_RD_WAIT =>
                  if (ddram_done = '1') then
                     state         <= IDLE;
                     bus_cart_done <= '1';
                     if (dd_ipl_rd_half = '0') then
                        bus_cart_dataRead <= ddram_dataRead(7 downto 0) & ddram_dataRead(15 downto 8) &
                                             ddram_dataRead(23 downto 16) & ddram_dataRead(31 downto 24);
                     else
                        bus_cart_dataRead <= ddram_dataRead(39 downto 32) & ddram_dataRead(47 downto 40) &
                                             ddram_dataRead(55 downto 48) & ddram_dataRead(63 downto 56);
                     end if;
                  end if;

               when READROM =>
                  if (sdram_done = '1') then
                     state             <= IDLE;
                     bus_cart_dataRead <= sdram_dataRead(7 downto 0) & sdram_dataRead(15 downto 8) & sdram_dataRead(23 downto 16) & sdram_dataRead(31 downto 24);
                     bus_cart_done     <= '1';
                  end if;
                  
               when READSRAM => 
                  if (sdram_done = '1') then
                     state             <= IDLE;
                     bus_cart_dataRead <= sdram_dataRead(7 downto 0) & sdram_dataRead(15 downto 8) & sdram_dataRead(23 downto 16) & sdram_dataRead(31 downto 24);
                     bus_cart_done     <= '1';
                  end if;               
                  
               when WRITESRAM => 
                  if (sdram_done = '1') then
                     state             <= IDLE;
                     bus_cart_done     <= '1';
                  end if;
                  
               when WRITEFLASH =>
                  state             <= WAITFLASH;
                  change_flash      <= '1';
                  flash_addrB       <= std_logic_vector(unsigned(flash_addrB) + 1);
                  sdram_request     <= '1';
                  sdram_rnw         <= '0';
                  sdram_writeMask   <= "1111";
                  sdram_address     <= (10x"0" & flash_offset & unsigned(flash_addrB) & "00") + to_unsigned(16#400000#, 27);
                  if (flashState = FLASHWRITE) then
                     sdram_dataWrite <= flash_DataOutB;
                  else
                     sdram_dataWrite <= (others => '1');
                  end if;

               when WAITFLASH =>
                  if (sdram_done = '1') then
                     if (flash_addrB = 5x"0") then
                        state           <= IDLE;
                        bus_cart_done   <= '1';
                     else
                        state           <= WRITEFLASH;
                     end if;
                  end if;
            
               when COPYDMABLOCK =>
                  if (copycnt < blocklength) then
                     state         <= DMA_READCART;
                     sdram_request <= '1';
                     sdram_rnw     <= '1';

                     dma_isflashread <= '0';
                     dma_is_ipl      <= '0';

                     rom_slow_sum <= rom_slow_sum + to_integer(PI_BSD_PWD) + to_integer(PI_BSD_RLS) + 2;

                     if ((dd_attached = '1') and dd_reg_selected(PI_CART_ADDR(28 downto 0))) then -- DD registers
                        state         <= DMA_READDD;
                        sdram_request <= '0';
                     elsif (dd_ipl_selected(PI_CART_ADDR(28 downto 0)) and ddIplAvailable = '1') then -- DD IPL ROM
                        -- Source the IPL aperture from the dedicated DDR copy, not SDRAM.
                        state         <= DMA_READCART;
                        sdram_request <= '0';
                        dma_is_ipl    <= '1';
                        ddram_request <= '1';
                        ddram_rnw     <= '1';
                        ddram_address <= DD_IPL_DDR_BASE + (6x"0" & PI_CART_ADDR(21 downto 3) & "000");
                     elsif (PI_CART_ADDR(28 downto 0) < 16#08000000#) then
                        null;
                     elsif (PI_CART_ADDR(28 downto 0) < 16#10000000#) then -- SRAM+FLASH  
                        if (SAVETYPE = "011") then
                           sdram_address <= (11x"0" & PI_CART_ADDR(14 downto 1) & '0') + to_unsigned(16#400000#, 27);
                        else
                           sdram_address <= (9x"0" &  PI_CART_ADDR(16 downto 1) & '0') + to_unsigned(16#400000#, 27);
                        end if;
                        if (SAVETYPE = "101") then
                           dma_isflashread <= '1';
                        end if;  
                     elsif (PI_CART_ADDR(28 downto 0) < (16#10000000# + to_integer(cartSize))) then -- game rom
                        sdram_address <= (PI_CART_ADDR(25 downto 1) & '0') + to_unsigned(16#1000000#, 27);
                     else
                        --report "Openbus DMA read not implemented" severity failure;
                        error_PI      <= '1';
                     end if;
                  elsif (PIfifo_nearfull = '0') then
                     state        <= IDLE;
                     first128     <= '0';
                     PI_DRAM_ADDR <= PI_DRAM_ADDR + 7;
                     PI_DRAM_ADDR(2 downto 0) <= "000";
                     if (distEndOfRowSave < 8) then
                        MaxBlockSize <= 128 - misAlignSave;
                     else
                        MaxBlockSize <= 128;
                     end if;
                     if (blocklength > 8) then
                        PI_WR_LEN <= 7x"7F";
                     else
                        PI_WR_LEN <= to_unsigned(127 - misAlignSave, 7);
                     end if;
                  end if;
                  
               when DMA_READDD =>
                  dd_offset := PI_CART_ADDR(10 downto 0);
                  if (dd_offset >= 11x"400" and dd_offset < 11x"500") then
                     dd_sector_addr_b <= std_logic_vector(dd_offset(7 downto 3));
                  end if;
                  state <= DMA_READDD_WAIT;

               when DMA_READDD_WAIT =>
                  state <= DMA_READDD_DATA;

               when DMA_READDD_DATA =>
                  state        <= COPYDMABLOCK;
                  PIfifo_Din(84 downto 64)   <= std_logic_vector(PI_DRAM_ADDR(23 downto 3));

                  copycnt      <= copycnt + 2;
                  PI_CART_ADDR <= PI_CART_ADDR + 2;
                  if (PI_LEN > 2) then
                     PI_LEN    <= PI_LEN - 2;
                  else
                     PI_LEN    <= (others => '0');
                  end if;

                  if (PI_DRAM_valid = '0' or ((PI_DRAM_ADDR(17 downto 0) and PI_DRAM_pagemask) /= (PI_DRAM_page and PI_DRAM_pagemask))) then
                     PI_DRAM_page  <= PI_DRAM_ADDR(17 downto 0);
                     rom_slow_sum  <= rom_slow_sum + to_integer(PI_BSD_LAT);
                     PI_DRAM_valid <= '1';
                  end if;

                  writemask_new := "00";
                  if (copycnt < maxram) then
                     writemask_new(0) := '1';
                     writemask_new(1) := '1';
                  end if;
                  if (first128 = '1' and blocklength < 127 - misAlignSave) then
                     if (copycnt >= maxram - 1) then
                        writemask_new(1) := '0';
                     end if;
                  end if;

                  if (writemask_new(0) = '1') then
                     PIfifo_Wr   <= '1';
                  end if;

                  if (writemask_new(1) = '1') then
                     PI_DRAM_ADDR <= PI_DRAM_ADDR + 2;
                  elsif (writemask_new(0) = '1') then
                     PI_DRAM_ADDR <= PI_DRAM_ADDR + 1;
                  end if;

                  if (PI_DRAM_ADDR(0) = '1' and writemask_new /= "00") then
                     report "Unaligned PI DMA write" severity failure;
                  end if;

                  dd_offset    := PI_CART_ADDR(10 downto 0);
                  if (dd_offset >= 11x"400" and dd_offset < 11x"500") then
                     case dd_offset(2 downto 1) is
                        when "00" => dma_readData := dd_sector_data_out_b0;
                        when "01" => dma_readData := dd_sector_data_out_b1;
                        when "10" => dma_readData := dd_sector_data_out_b2;
                        when "11" => dma_readData := dd_sector_data_out_b3;
                        when others => null;
                     end case;
                  else
                     dma_readData := dd_read_half(dd_offset);
                  end if;
                  dma_fifoData := dma_readData;
                  if (dd_offset >= 11x"400" and dd_offset < 11x"500") then
                     if (dd_offset < 11x"408") then
                        case dd_offset(2 downto 1) is
                           when others => null;
                        end case;
                     end if;
                  end if;

                  case (PI_DRAM_ADDR(2 downto 1)) is
                     when "00" => PIfifo_Din(15 downto  0) <= dma_fifoData; PIfifo_Din(92 downto 85) <= "000000" & writemask_new;
                     when "01" => PIfifo_Din(31 downto 16) <= dma_fifoData; PIfifo_Din(92 downto 85) <= "0000" & writemask_new & "00";
                     when "10" => PIfifo_Din(47 downto 32) <= dma_fifoData; PIfifo_Din(92 downto 85) <= "00" & writemask_new & "0000";
                     when "11" => PIfifo_Din(63 downto 48) <= dma_fifoData; PIfifo_Din(92 downto 85) <= writemask_new & "000000";
                     when others => null;
                  end case;

                  if (dd_is_cmd_status_offset(dd_offset)) then
                     -- ares: a status read that observes the BM interrupt ACKs it
                     -- and schedules the next buffer-manager request.
                     if (dd_bm_interrupt = '1') then
                        dd_bm_interrupt <= '0';
                        dd_sector_advance_pending <= '1';
                        dd_sector_advance_counter <= DD_BM_NEXT_DELAY_CLK1X;
                     end if;
                  end if;

               when DMA_READCART =>
                  if ((dma_is_ipl = '0' and sdram_done = '1') or (dma_is_ipl = '1' and ddram_done = '1')) then

                     state        <= COPYDMABLOCK;
                     PIfifo_Din(84 downto 64)   <= std_logic_vector(PI_DRAM_ADDR(23 downto 3));
                  
                     copycnt      <= copycnt + 2;
                     PI_CART_ADDR <= PI_CART_ADDR + 2;
                     if (PI_LEN > 2) then
                        PI_LEN    <= PI_LEN - 2;
                     else
                        PI_LEN    <= (others => '0');
                     end if;
                     
                     if (PI_DRAM_valid = '0' or ((PI_DRAM_ADDR(17 downto 0) and PI_DRAM_pagemask) /= (PI_DRAM_page and PI_DRAM_pagemask))) then
                        PI_DRAM_page  <= PI_DRAM_ADDR(17 downto 0);
                        rom_slow_sum  <= rom_slow_sum + to_integer(PI_BSD_LAT);
                        PI_DRAM_valid <= '1';
                     end if;
                     
                     writemask_new := "00";
                     if (copycnt < maxram) then
                        writemask_new(0) := '1';
                        writemask_new(1) := '1';
                     end if;
                     if (first128 = '1' and blocklength < 127 - misAlignSave) then
                        if (copycnt >= maxram - 1) then 
                           writemask_new(1) := '0';
                        end if;
                     end if;
                     
                     if (writemask_new(0) = '1') then
                        PIfifo_Wr   <= '1';
                     end if;
                     
                     if (writemask_new(1) = '1') then
                        PI_DRAM_ADDR <= PI_DRAM_ADDR + 2;
                     elsif (writemask_new(0) = '1') then
                        PI_DRAM_ADDR <= PI_DRAM_ADDR + 1;
                     end if;
                     
                     if (PI_DRAM_ADDR(0) = '1' and writemask_new /= "00") then
                        report "Unaligned PI DMA write" severity failure;  
                     end if;
                     
                     if (dma_is_ipl = '1') then
                        -- IPL aperture sourced from the DDR copy: raw big-endian
                        -- halfword selected by the cart address, matching the
                        -- byte-copy semantics of the SDRAM cartridge DMA path.
                        case (PI_CART_ADDR(2 downto 1)) is
                           when "00" => dma_readData := ddram_dataRead(15 downto 0);
                           when "01" => dma_readData := ddram_dataRead(31 downto 16);
                           when "10" => dma_readData := ddram_dataRead(47 downto 32);
                           when "11" => dma_readData := ddram_dataRead(63 downto 48);
                           when others => null;
                        end case;
                     else
                        dma_readData := sdram_dataRead(15 downto 0);
                     end if;

                     if (dma_isflashread = '1') then
                        if (flashState = FLASHSTATUS) then
                           case (PI_CART_ADDR(2 downto 1)) is
                              when "00" => dma_readData := byteswap16(flash_statusword(63 downto 48));
                              when "01" => dma_readData := byteswap16(flash_statusword(47 downto 32));
                              when "10" => dma_readData := byteswap16(flash_statusword(31 downto 16));
                              when "11" => dma_readData := byteswap16(flash_statusword(15 downto 0));
                              when others => null;
                           end case;
                        elsif (flashState /= FLASHREAD) then
                           dma_readData := (others => '0');
                        end if;
                     end if;
                     
                     case (PI_DRAM_ADDR(2 downto 1)) is
                        when "00" => PIfifo_Din(15 downto  0) <= dma_readData; PIfifo_Din(92 downto 85) <= "000000" & writemask_new;
                        when "01" => PIfifo_Din(31 downto 16) <= dma_readData; PIfifo_Din(92 downto 85) <= "0000" & writemask_new & "00";
                        when "10" => PIfifo_Din(47 downto 32) <= dma_readData; PIfifo_Din(92 downto 85) <= "00" & writemask_new & "0000";
                        when "11" => PIfifo_Din(63 downto 48) <= dma_readData; PIfifo_Din(92 downto 85) <= writemask_new & "000000";
                        when others => null;
                     end case;
                     
                  end if;
                  
               when DMA_READRDRAM =>
                  if (copycnt < blocklength) then
                     state            <= DMA_WAITRDRAM;
                     rdram_request   <= '1';
                     rdram_rnw       <= '1';
                     rdram_address   <= "0000" & PI_DRAM_ADDR(23 downto 3) & "000";
                  else
                     state <= IDLE;
                     PI_DRAM_ADDR <= PI_DRAM_ADDR + 7;
                     PI_DRAM_ADDR(2 downto 0) <= "000";
                     PI_CART_ADDR <= PI_CART_ADDR + 1;
                     PI_CART_ADDR(0) <= '0';
                  end if;

               when DMA_WAITRDRAM =>
                  if (rdram_done = '1') then
                  
                     sdram_dataWrite <= rdram_dataRead(15 downto  0) & rdram_dataRead(15 downto  0);
                     dd_wdata        := rdram_dataRead(15 downto 0);
                     case (PI_DRAM_ADDR(2 downto 1)) is
                        when "00" => sdram_dataWrite <= rdram_dataRead(15 downto  0) & rdram_dataRead(15 downto  0); flash_DataInA <= rdram_dataRead(15 downto  0); dd_wdata := rdram_dataRead(15 downto 0);
                        when "01" => sdram_dataWrite <= rdram_dataRead(31 downto 16) & rdram_dataRead(31 downto 16); flash_DataInA <= rdram_dataRead(31 downto 16); dd_wdata := rdram_dataRead(31 downto 16);
                        when "10" => sdram_dataWrite <= rdram_dataRead(47 downto 32) & rdram_dataRead(47 downto 32); flash_DataInA <= rdram_dataRead(47 downto 32); dd_wdata := rdram_dataRead(47 downto 32);
                        when "11" => sdram_dataWrite <= rdram_dataRead(63 downto 48) & rdram_dataRead(63 downto 48); flash_DataInA <= rdram_dataRead(63 downto 48); dd_wdata := rdram_dataRead(63 downto 48);
                        when others => null;
                     end case;
                     
                     if (PI_CART_ADDR(1) = '1') then
                        sdram_writeMask  <= "1100";
                     else
                        sdram_writeMask  <= "0011";
                     end if;
                     
                     if (SAVETYPE = "011") then
                        sdram_address <= (11x"0" & PI_CART_ADDR(14 downto 2) & "00") + to_unsigned(16#400000#, 27);
                     else
                        sdram_address <= (9x"0" &  PI_CART_ADDR(16 downto 2) & "00") + to_unsigned(16#400000#, 27);
                     end if;
                     
                     flash_addrA <= std_logic_vector(PI_CART_ADDR(6 downto 1));
                     
                     state   <= DMA_READRDRAM;
                     copycnt <= copycnt + 2;
                     PI_DRAM_ADDR <= PI_DRAM_ADDR + 2;
                     PI_CART_ADDR <= PI_CART_ADDR + 2;
                        
                     if ((dd_attached = '1') and dd_reg_selected(PI_CART_ADDR(28 downto 0))) then -- DD registers
                        dd_offset := PI_CART_ADDR(10 downto 0);
                        if (dd_offset >= 11x"400" and dd_offset < 11x"500") then
                           dd_writeData := dd_wdata;
                           dd_sector_addr_b     <= std_logic_vector(dd_offset(7 downto 3));
                           dd_sector_data_in_b0 <= dd_writeData;
                           dd_sector_data_in_b1 <= dd_writeData;
                           dd_sector_data_in_b2 <= dd_writeData;
                           dd_sector_data_in_b3 <= dd_writeData;
                           case dd_offset(2 downto 1) is
                              when "00" => dd_sector_wren_b(0) <= '1';
                              when "01" => dd_sector_wren_b(1) <= '1';
                              when "10" => dd_sector_wren_b(2) <= '1';
                              when "11" => dd_sector_wren_b(3) <= '1';
                              when others => null;
                           end case;
                           if dd_offset(7 downto 1) = dd_sector_size(7 downto 1) then
                              dd_write_sector_ready <= '1';
                           end if;
                        else
                           -- DMA writes through the ASIC window are visible on hardware, but treating
                           -- the whole DMA stream as register writes clobbers live BM geometry.
                           null;
                        end if;
                     elsif (PI_CART_ADDR(28 downto 0) < 16#08000000#) then
                        null;
                     elsif (PI_CART_ADDR(28 downto 0) < 16#10000000#) then -- SRAM+FLASH  
                        if (SAVETYPE = "011" or SAVETYPE = "100") then
                           change_sram   <= '1';
                           state         <= DMA_WAITSDRAM;
                           sdram_request <= '1';
                           sdram_rnw     <= '0';
                        elsif (SAVETYPE = "101") then
                           flash_wrenA <= '1';
                        end if;
                     elsif (PI_CART_ADDR(28 downto 0) < (16#10000000# + to_integer(cartSize))) then -- game rom
                        report "Cart DMA write not implemented" severity failure;
                        error_PI      <= '1';
                     else
                        report "Openbus DMA write not implemented" severity failure;
                        error_PI      <= '1';
                     end if;
                     
                     
                  end if;
                           
               when DMA_WAITSDRAM =>
                  if (sdram_done = '1') then
                     state <= DMA_READRDRAM;
                  end if;

               when DD_LOAD_REQ =>
                  if (ddDiskAvailable = '1') then
                     ddram_request <= '1';
                     ddram_address <= dd_load_addr + to_unsigned(dd_load_count * 8, 28);
                     state         <= DD_LOAD_WAIT;
                  else
                     dd_bm_micro_error   <= '1';
                     dd_bm_interrupt     <= '1';
                     dd_bm_transfer_data <= '0';
                     state               <= IDLE;
                  end if;

               when DD_LOAD_WAIT =>
                  if (ddram_done = '1') then
                     dd_sector_addr_a <= std_logic_vector(to_unsigned(dd_load_count, dd_sector_addr_a'length));
                     dd_sector_data_a0 <= ddram_dataRead(15 downto 0);
                     dd_sector_data_a1 <= ddram_dataRead(31 downto 16);
                     dd_sector_data_a2 <= ddram_dataRead(47 downto 32);
                     dd_sector_data_a3 <= ddram_dataRead(63 downto 48);
                     dd_sector_wren_a <= '1';

                     if ((dd_load_count + 1) >= dd_load_total) then
                        dd_next_sector := dd_current_sector + 1;
                        dd_current_sector <= dd_next_sector;
                        -- sentinel-marked unreadable block: report C1 failure like ares'
                        -- copy-protection path, but still deliver the buffer contents.
                        if (dd_load_count = 31 and ddram_dataRead = DD_BAD_BLOCK_SENTINEL) then
                           dd_bm_c1_single <= '1';
                           dd_bm_c1_double <= '1';
                        end if;
                        dd_bm_transfer_data   <= '1';
                        dd_bm_interrupt       <= '1';
                        state                 <= IDLE;
                     else
                        dd_load_count <= dd_load_count + 1;
                        state         <= DD_LOAD_REQ;
                     end if;
                  end if;

               when DD_STORE_READ =>
                  dd_sector_addr_a <= std_logic_vector(to_unsigned(dd_store_count, dd_sector_addr_a'length));
                  state            <= DD_STORE_REQ;

               -- dpram port A has 1-cycle registered-address read latency, so the
               -- address set in DD_STORE_READ is not stable until this cycle and
               -- q_a is not valid until DD_STORE_ISSUE. (Mirrors the read path:
               -- DMA_READDD -> DMA_READDD_WAIT -> DMA_READDD_DATA.)
               when DD_STORE_REQ =>
                  state <= DD_STORE_ISSUE;

               when DD_STORE_ISSUE =>
                  ddram_request   <= '1';
                  ddram_rnw       <= '0';
                  ddram_address   <= dd_store_addr + to_unsigned(dd_store_count * 8, 28);
                  ddram_writeMask <= x"FF";
                  ddram_dataWrite <= dd_sector_data_out_a3 & dd_sector_data_out_a2 &
                                     dd_sector_data_out_a1 & dd_sector_data_out_a0;
                  state           <= DD_STORE_WAIT;

               when DD_STORE_WAIT =>
                  -- DDR3Mux queues only the request bit. Keep the write controls
                  -- stable until it services the queued request and raises done.
                  ddram_rnw       <= '0';
                  ddram_address   <= dd_store_addr + to_unsigned(dd_store_count * 8, 28);
                  ddram_writeMask <= x"FF";
                  ddram_dataWrite <= dd_sector_data_out_a3 & dd_sector_data_out_a2 &
                                     dd_sector_data_out_a1 & dd_sector_data_out_a0;
                  if (ddram_done = '1') then
                     if (dd_store_count = 31) then
                        state <= DD_DIRTY_WRITE;
                     else
                        dd_store_count <= dd_store_count + 1;
                        state          <= DD_STORE_READ;
                     end if;
                  end if;

               -- mark the block dirty in the flat DDR image so Main_MiSTer's
               -- write-back poll can persist it to the disk file on SD card
               when DD_DIRTY_WRITE =>
                  ddram_request   <= '1';
                  ddram_rnw       <= '0';
                  ddram_address   <= dd_dirty_addr;
                  ddram_writeMask <= x"FF";
                  ddram_dataWrite <= DD_DIRTY_MAGIC;
                  state           <= DD_DIRTY_WAIT;

               when DD_DIRTY_WAIT =>
                  ddram_rnw       <= '0';
                  ddram_address   <= dd_dirty_addr;
                  ddram_writeMask <= x"FF";
                  ddram_dataWrite <= DD_DIRTY_MAGIC;
                  if (ddram_done = '1') then
                     dd_current_sector    <= dd_store_next_sector;
                     dd_bm_transfer_data  <= dd_store_set_data;
                     if (dd_store_stop = '1') then
                        dd_bm_running     <= '0';
                        dd_bm_stop_reason <= x"5";
                     end if;
                     dd_bm_interrupt <= '1';
                     state           <= IDLE;
                  end if;
                  
                  
            end case;

         end if;
      end if;
   end process;
   
   iflashpage: entity work.dpram_dif
   generic map 
   ( 
      addr_width_a  => 6,
      data_width_a  => 16,
      addr_width_b  => 5,
      data_width_b  => 32
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => flash_addrA,
      data_a      => flash_DataInA,
      wren_a      => flash_wrenA,
      q_a         => open,
      
      clock_b     => clk1x,
      address_b   => flash_addrB,
      data_b      => 32x"0",
      wren_b      => '0',
      q_b         => flash_DataOutB
   );

   iddsector0: entity work.dpram
   generic map
   (
      addr_width => 5,
      data_width => 16
   )
   port map
   (
      clock_a   => clk1x,
      address_a => dd_sector_addr_a,
      data_a    => dd_sector_data_a0,
      wren_a    => dd_sector_wren_a,
      q_a       => dd_sector_data_out_a0,

      clock_b   => clk1x,
      address_b => dd_sector_addr_b,
      data_b    => dd_sector_data_in_b0,
      wren_b    => dd_sector_wren_b(0),
      q_b       => dd_sector_data_out_b0
   );

   iddsector1: entity work.dpram
   generic map
   (
      addr_width => 5,
      data_width => 16
   )
   port map
   (
      clock_a   => clk1x,
      address_a => dd_sector_addr_a,
      data_a    => dd_sector_data_a1,
      wren_a    => dd_sector_wren_a,
      q_a       => dd_sector_data_out_a1,

      clock_b   => clk1x,
      address_b => dd_sector_addr_b,
      data_b    => dd_sector_data_in_b1,
      wren_b    => dd_sector_wren_b(1),
      q_b       => dd_sector_data_out_b1
   );

   iddsector2: entity work.dpram
   generic map
   (
      addr_width => 5,
      data_width => 16
   )
   port map
   (
      clock_a   => clk1x,
      address_a => dd_sector_addr_a,
      data_a    => dd_sector_data_a2,
      wren_a    => dd_sector_wren_a,
      q_a       => dd_sector_data_out_a2,

      clock_b   => clk1x,
      address_b => dd_sector_addr_b,
      data_b    => dd_sector_data_in_b2,
      wren_b    => dd_sector_wren_b(2),
      q_b       => dd_sector_data_out_b2
   );

   iddsector3: entity work.dpram
   generic map
   (
      addr_width => 5,
      data_width => 16
   )
   port map
   (
      clock_a   => clk1x,
      address_a => dd_sector_addr_a,
      data_a    => dd_sector_data_a3,
      wren_a    => dd_sector_wren_a,
      q_a       => dd_sector_data_out_a3,

      clock_b   => clk1x,
      address_b => dd_sector_addr_b,
      data_b    => dd_sector_data_in_b3,
      wren_b    => dd_sector_wren_b(3),
      q_b       => dd_sector_data_out_b3
   );
   
--##############################################################
--############################### savestates
--##############################################################

   SS_idle <= '1';

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (SS_reset = '1') then
         
            for i in 0 to 5 loop
               ss_in(i) <= (others => '0');
            end loop;
            
         elsif (SS_wren = '1') then
            ss_in(to_integer(SS_Adr)) <= SS_DataWrite;
         end if;
         
         if (SS_rden = '1') then
            SS_DataRead <= ss_out(to_integer(SS_Adr));
         end if;
      
      end if;
   end process;
   
      
--##############################################################
--############################### export
--##############################################################
   
   -- synthesis translate_off
   goutput : if 1 = 1 generate
      signal out_count        : unsigned(31 downto 0) := (others => '0');
      signal exportindex      : unsigned(15 downto 0);
   begin
   
      process
         file outfile           : text;
         variable f_status      : FILE_OPEN_STATUS;
         variable line_out      : line;
         variable stringbuffer  : string(1 to 31);
         
         variable exportaddress : unsigned(31 downto 0);
         variable exportdata    : unsigned(63 downto 0);
         variable out_count_new : unsigned(31 downto 0);
      begin
   
         file_open(f_status, outfile, "R:\\PI_n64_sim.txt", write_mode);
         file_close(outfile);
         file_open(f_status, outfile, "R:\\PI_n64_sim.txt", append_mode);
         
         while (true) loop
         
            if (reset = '1') then
               file_close(outfile);
               file_open(f_status, outfile, "R:\\PI_n64_sim.txt", write_mode);
               file_close(outfile);
               file_open(f_status, outfile, "R:\\PI_n64_sim.txt", append_mode);
               out_count <= (others => '0');
               exportindex <= (others => '0');
            end if;
            
            wait until rising_edge(clk1x);

            --if (rdram_request = '1' and rdram_rnw = '0') then
            --   
            --   exportaddress := x"0" & rdram_address;
            --   exportdata    := unsigned(rdram_dataWrite);
            --   
            --   out_count_new := out_count;
            --   for i in 0 to 7 loop
            --      if (rdram_writeMask(i) = '1') then
            --         write(line_out, to_hstring(exportindex));
            --         write(line_out, string'(" "));                    
            --         write(line_out, to_hstring(exportaddress));
            --         write(line_out, string'(" "));
            --         write(line_out, to_hstring(exportdata(7 downto 0)));
            --         writeline(outfile, line_out);
            --         out_count_new := out_count_new + 1;
            --      end if;
            --      
            --      exportdata := x"00" & exportdata(63 downto 8);
            --      exportaddress := exportaddress + 1;
            --   end loop;
            --   out_count <= out_count_new;
            --   
            --end if;
            
            if (state = IDLE and dmaIsWrite = '1' and PI_STATUS_DMAbusy = '1' and PI_LEN = 0) then
               file_close(outfile);
               file_open(f_status, outfile, "R:\\PI_n64_sim.txt", append_mode);
               exportindex <= exportindex + 1;
            end if;
            
         end loop;
         
      end process;
   
   end generate goutput;

   -- synthesis translate_on  

end architecture;





