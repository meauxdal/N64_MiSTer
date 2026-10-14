-- Mode/address tests do not inspect rendered pixel data. These zero-output
-- RAM stubs let GHDL elaborate the complete VI without Altera simulation IP.
library ieee;
use ieee.std_logic_1164.all;
entity dpram is
   generic (addr_width : integer := 8; data_width : integer := 8);
   port (
      clock_a : in std_logic; clken_a : in std_logic := '1';
      address_a : in std_logic_vector(addr_width-1 downto 0);
      data_a : in std_logic_vector(data_width-1 downto 0);
      wren_a : in std_logic := '0'; q_a : out std_logic_vector(data_width-1 downto 0);
      clock_b : in std_logic; clken_b : in std_logic := '1';
      address_b : in std_logic_vector(addr_width-1 downto 0);
      data_b : in std_logic_vector(data_width-1 downto 0) := (others=>'0');
      wren_b : in std_logic := '0'; q_b : out std_logic_vector(data_width-1 downto 0));
end;
architecture stub of dpram is begin q_a <= (others=>'0'); q_b <= (others=>'0'); end;

library ieee;
use ieee.std_logic_1164.all;
entity dpram_dif is
   generic (addr_width_a : integer := 8; data_width_a : integer := 8;
            addr_width_b : integer := 8; data_width_b : integer := 8);
   port (
      clock_a : in std_logic;
      address_a : in std_logic_vector(addr_width_a-1 downto 0) := (others=>'0');
      data_a : in std_logic_vector(data_width_a-1 downto 0) := (others=>'0');
      clken_a : in std_logic := '1'; wren_a : in std_logic := '0';
      q_a : out std_logic_vector(data_width_a-1 downto 0); cs_a : in std_logic := '1';
      clock_b : in std_logic;
      address_b : in std_logic_vector(addr_width_b-1 downto 0) := (others=>'0');
      data_b : in std_logic_vector(data_width_b-1 downto 0) := (others=>'0');
      clken_b : in std_logic := '1'; wren_b : in std_logic := '0';
      q_b : out std_logic_vector(data_width_b-1 downto 0); cs_b : in std_logic := '1');
end;
architecture stub of dpram_dif is begin q_a <= (others=>'0'); q_b <= (others=>'0'); end;

-- Overlays are disabled in the mode test. Unconstrained coordinates avoid
-- GHDL rejecting the production overlay's bounded integer port conversions.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity VI_overlay is
   generic (COLS : natural; OFFSETX : integer range 0 to 2047;
            OFFSETY : integer range 0 to 1023; RGB_FRONT : std_logic_vector(23 downto 0));
   port (clk, ce, ena : in std_logic;
         i_pixel_out_x, i_pixel_out_y : in integer;
         o_pixel_out_data : out std_logic_vector(RGB_FRONT'range);
         o_pixel_out_ena : out std_logic;
         textstring : in unsigned(0 to COLS*8-1));
end;
architecture stub of VI_overlay is
begin o_pixel_out_data <= (others=>'0'); o_pixel_out_ena <= '0'; end;
