library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity savestates is
   generic
   (
      FASTSIM        : std_logic;
      SAVETYPESCOUNT : integer := 14
   );
   port
   (
      clk1x                   : in  std_logic;
      clk93                   : in  std_logic;
      reset_in                : in  std_logic;
      softreset               : in  std_logic;
      reset_out_1x            : out std_logic := '0';
      reset_out_93            : out std_logic := '0';
      ss_reset_1x             : out std_logic := '0';
      ss_reset_93             : out std_logic := '0';
      cpu_PRENMI              : out std_logic := '0';
      PIF_Softreset           : out std_logic := '0';

      RAMSIZE8                : in  std_logic;

      hps_busy                : in  std_logic;
      sdrammux_idle           : in  std_logic;

      load_done               : out std_logic := '0';

      increaseSSHeaderCount   : in  std_logic;
      save                    : in  std_logic;
      load                    : in  std_logic;
      savestate_address       : in  integer;
      savestate_busy          : out std_logic;

      SS_idle                 : in  std_logic;
      system_paused           : in  std_logic;
      savestate_pause         : out std_logic := '0';

      SS_DataWrite            : out std_logic_vector(63 downto 0) := (others => '0');
      SS_Adr                  : out unsigned(11 downto 0) := (others => '0');
      SS_wren                 : out std_logic_vector(SAVETYPESCOUNT - 1 downto 0);
      SS_rden                 : out std_logic_vector(SAVETYPESCOUNT - 1 downto 0);
      SS_DataRead_CPU         : in  std_logic_vector(63 downto 0) := (others => '0');

      SS_DataWrite_93         : out std_logic_vector(63 downto 0) := (others => '0');
      SS_Adr_93               : out unsigned(11 downto 0) := (others => '0');
      SS_wren_93              : out std_logic_vector(SAVETYPESCOUNT - 1 downto 0);

      loading_savestate       : out std_logic := '0';
      saving_savestate        : out std_logic := '0';

      romcopy_start           : in  std_logic;
      romcopy_size            : in  unsigned(26 downto 0);
      romcopy_nearFull        : in  std_logic;
      romcopy_active          : out std_logic := '0';

      rdram_request           : out std_logic := '0';
      rdram_rnw               : out std_logic := '0';
      rdram_address           : out unsigned(27 downto 0):= (others => '0');
      rdram_burstcount        : out unsigned(9 downto 0):= (others => '0');
      rdram_writeMask         : out std_logic_vector(7 downto 0) := (others => '0');
      rdram_dataWrite         : out std_logic_vector(63 downto 0) := (others => '0');
      rdram_done              : in  std_logic;
      rdram_dataRead          : in  std_logic_vector(63 downto 0)
   );
end entity;

architecture arch of savestates is

   constant ROMCOPY_BASE_WORD : unsigned(24 downto 0) := to_unsigned(16#400000#, 25);
   constant CLEAR_WORDS       : unsigned(24 downto 0) := to_unsigned(16#102000#, 25);

   type tstate is
   (
      IDLE,
      ROMCOPY_SETTLE,
      ROMCOPY_REQUEST,
      ROMCOPY_READ,
      POSTCOPY_DRAIN,
      CLEAR_RDRAM_REQ,
      CLEAR_RDRAM_WAIT,
      INITRAMSIZE1_REQ,
      INITRAMSIZE1_WAIT,
      INITRAMSIZE2_REQ,
      INITRAMSIZE2_WAIT,
      RESETTING,
      SOFTRESET_START
   );

   signal state                : tstate := IDLE;
   signal romcopy_latched      : std_logic := '0';
   signal ram_addr_next        : unsigned(24 downto 0) := (others => '0');
   signal clear_addr_next      : unsigned(24 downto 0) := (others => '0');
   signal settle               : integer range 0 to 31 := 0;
   signal reset_1x_int         : std_logic := '0';
   signal ss_reset_1x_int      : std_logic := '0';

   -- soft reset (reset button / PRENMI) resets only the CPU + PIF (93 domain);
   -- the 1x domain (RDP/RSP/VI) keeps running, matching the upstream behaviour.
   signal reset_cpu_int        : std_logic := '0';
   signal ss_reset_cpu_int     : std_logic := '0';
   signal softreset_1          : std_logic := '0';
   signal cpu_PRENMI_1x        : std_logic := '0';
   signal softreset_wait       : unsigned(25 downto 0) := (others => '0');

begin

   savestate_busy <= '0' when (state = IDLE and romcopy_latched = '0') else '1';

   SS_DataWrite      <= (others => '0');
   SS_Adr            <= (others => '0');
   SS_wren           <= (others => '0');
   SS_rden           <= (others => '0');
   SS_DataWrite_93   <= (others => '0');
   SS_Adr_93         <= (others => '0');
   SS_wren_93        <= (others => '0');
   loading_savestate <= '0';
   saving_savestate  <= '0';
   load_done         <= '0';

   rdram_burstcount  <= to_unsigned(1, rdram_burstcount'length);
   rdram_writeMask   <= x"FF";

   reset_out_1x <= reset_1x_int;
   ss_reset_1x  <= ss_reset_1x_int;

   process (clk93)
   begin
      if rising_edge(clk93) then
         reset_out_93 <= reset_1x_int    or reset_cpu_int;
         ss_reset_93  <= ss_reset_1x_int or ss_reset_cpu_int;
         cpu_PRENMI   <= cpu_PRENMI_1x;
      end if;
   end process;

   process (clk1x)
      variable romcopy_end_word : unsigned(24 downto 0);
   begin
      if rising_edge(clk1x) then

         romcopy_end_word := ROMCOPY_BASE_WORD + resize(romcopy_size(26 downto 3), ROMCOPY_BASE_WORD'length);

         reset_1x_int     <= reset_in;
         ss_reset_1x_int  <= reset_in;
         reset_cpu_int    <= '0';
         ss_reset_cpu_int <= '0';
         cpu_PRENMI_1x    <= '0';
         PIF_Softreset    <= '0';
         rdram_request    <= '0';
         rdram_rnw        <= '1';

         if (romcopy_start = '1') then
            romcopy_latched <= '1';
         end if;

         softreset_wait <= softreset_wait + 1;

         case state is
            when IDLE =>
               romcopy_active  <= '0';
               savestate_pause <= reset_in;
               settle          <= 0;

               if (romcopy_latched = '1') then
                  romcopy_latched <= '0';
                  romcopy_active  <= '1';
                  savestate_pause <= '1';
                  reset_1x_int    <= '1';
                  ss_reset_1x_int <= '1';
                  ram_addr_next   <= ROMCOPY_BASE_WORD;
                  state           <= ROMCOPY_SETTLE;
               elsif (softreset = '1' and softreset_1 = '0') then
                  state           <= SOFTRESET_START;
                  softreset_wait  <= (others => '0');
               end if;

            when ROMCOPY_SETTLE =>
               romcopy_active  <= '1';
               savestate_pause <= '1';
               reset_1x_int    <= '1';
               ss_reset_1x_int <= '1';

               if (settle = 8) then
                  settle <= 0;
                  state  <= ROMCOPY_REQUEST;
               else
                  settle <= settle + 1;
               end if;

            when ROMCOPY_REQUEST =>
               romcopy_active  <= '1';
               savestate_pause <= '1';

               if (ram_addr_next >= romcopy_end_word) then
                  romcopy_active <= '0';
                  settle         <= 0;
                  state          <= POSTCOPY_DRAIN;
               elsif (romcopy_nearFull = '0') then
                  rdram_request <= '1';
                  rdram_rnw     <= '1';
                  rdram_address <= ram_addr_next & "000";
                  state         <= ROMCOPY_READ;
               end if;

            when ROMCOPY_READ =>
               romcopy_active  <= '1';
               savestate_pause <= '1';

               if (rdram_done = '1') then
                  ram_addr_next <= ram_addr_next + 1;
                  state         <= ROMCOPY_REQUEST;
               end if;

            when POSTCOPY_DRAIN =>
               savestate_pause <= '1';
               reset_1x_int    <= '1';

               if (settle < 16) then
                  settle <= settle + 1;
               elsif (sdrammux_idle = '1') then
                  clear_addr_next <= (others => '0');
                  state           <= CLEAR_RDRAM_REQ;
               end if;

            when CLEAR_RDRAM_REQ =>
               savestate_pause <= '1';
               reset_1x_int    <= '1';

               if (clear_addr_next >= CLEAR_WORDS) then
                  state <= INITRAMSIZE1_REQ;
               else
                  rdram_request   <= '1';
                  rdram_rnw       <= '0';
                  rdram_address   <= clear_addr_next & "000";
                  rdram_dataWrite <= (others => '0');
                  state           <= CLEAR_RDRAM_WAIT;
               end if;

            when CLEAR_RDRAM_WAIT =>
               savestate_pause <= '1';
               reset_1x_int    <= '1';

               if (rdram_done = '1') then
                  clear_addr_next <= clear_addr_next + 1;
                  state           <= CLEAR_RDRAM_REQ;
               end if;

            when INITRAMSIZE1_REQ =>
               savestate_pause <= '1';
               reset_1x_int    <= '1';
               rdram_request   <= '1';
               rdram_rnw       <= '0';
               rdram_address   <= to_unsigned(16#318#, rdram_address'length);
               if (RAMSIZE8 = '1') then
                  rdram_dataWrite <= std_logic_vector(to_unsigned(16#8000#, rdram_dataWrite'length));
               else
                  rdram_dataWrite <= std_logic_vector(to_unsigned(16#4000#, rdram_dataWrite'length));
               end if;
               state <= INITRAMSIZE1_WAIT;

            when INITRAMSIZE1_WAIT =>
               savestate_pause <= '1';
               reset_1x_int    <= '1';
               if (rdram_done = '1') then
                  state <= INITRAMSIZE2_REQ;
               end if;

            when INITRAMSIZE2_REQ =>
               savestate_pause <= '1';
               reset_1x_int    <= '1';
               rdram_request   <= '1';
               rdram_rnw       <= '0';
               rdram_address   <= to_unsigned(16#3F0#, rdram_address'length);
               if (RAMSIZE8 = '1') then
                  rdram_dataWrite <= std_logic_vector(to_unsigned(16#8000#, rdram_dataWrite'length));
               else
                  rdram_dataWrite <= std_logic_vector(to_unsigned(16#4000#, rdram_dataWrite'length));
               end if;
               state <= INITRAMSIZE2_WAIT;

            when INITRAMSIZE2_WAIT =>
               savestate_pause <= '1';
               reset_1x_int    <= '1';
               if (rdram_done = '1') then
                  settle <= 0;
                  state  <= RESETTING;
               end if;

            when RESETTING =>
               savestate_pause <= '1';
               reset_1x_int    <= '1';

               if (settle < 16) then
                  settle <= settle + 1;
               elsif (reset_in = '0' and sdrammux_idle = '1') then
                  savestate_pause <= '0';
                  state           <= IDLE;
               end if;

            -- soft reset (reset button): send the CPU a pre-NMI, then after the
            -- hardware-accurate delay pulse the CPU/PIF reset. RDRAM is preserved
            -- (no romcopy) and the 1x domain is left running.
            when SOFTRESET_START =>
               if (softreset_wait = 60) then
                  cpu_PRENMI_1x <= '1';
               end if;
               if ((FASTSIM = '1' and softreset_wait = 10000) or (FASTSIM = '0' and softreset_wait = 31250000)) then
                  ss_reset_cpu_int <= '1';
                  savestate_pause  <= '1';
               end if;
               if ((FASTSIM = '1' and softreset_wait = 20000) or (FASTSIM = '0' and softreset_wait = 31260000)) then
                  state         <= IDLE;
                  reset_cpu_int <= '1';
                  PIF_Softreset <= '1';
               end if;

            when others =>
               state <= IDLE;
         end case;

         softreset_1 <= softreset;
      end if;
   end process;


end architecture;
