--------------------------------------------------------------------------------
-- can_ioexpander_max10.vhd
--
-- Wrapper di top level per il target Intel MAX 10 (kit 10M08SAE144C8G, 50 MHz).
-- Istanzia can_ioexpander_top fissando i generic per un clock di 50 MHz:
--   BRP = 5  ->  Tq = 5/50MHz = 100 ns, 20 Tq/bit = 2 us = 500 kbit/s (sample 80%)
--   MS_TICKS = 50000  ->  base tempi di 1 ms a 50 MHz (periodo encoder)
--
-- Il resto del progetto (RTL) e' invariato e condiviso col target MAX V.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity can_ioexpander_max10 is
  port (
    clk       : in    std_logic;                       -- 50 MHz (oscillatore del kit)
    rst_n     : in    std_logic;
    can_rxd   : in    std_logic;
    can_txd   : out   std_logic;
    node_addr : in    std_logic_vector(3 downto 0);
    safe_ch1  : in    std_logic;
    safe_ch2  : in    std_logic;
    enc_a     : in    std_logic_vector(7 downto 0);
    enc_b     : in    std_logic_vector(7 downto 0);
    io        : inout std_logic_vector(31 downto 0);
    led_error : out   std_logic
  );
end entity can_ioexpander_max10;

architecture rtl of can_ioexpander_max10 is
begin

  u_top : entity work.can_ioexpander_top
    generic map (
      BRP           => 5,       -- 500 kbit/s con clock 50 MHz
      TSEG1         => 15,
      TSEG2         => 4,
      SJW           => 3,
      MS_TICKS      => 50000,   -- 1 ms @ 50 MHz
      ENC_PERIOD_MS => 10       -- trasmissione encoder ogni 10 ms (0 = off)
    )
    port map (
      clk       => clk,
      rst_n     => rst_n,
      can_rxd   => can_rxd,
      can_txd   => can_txd,
      node_addr => node_addr,
      safe_ch1  => safe_ch1,
      safe_ch2  => safe_ch2,
      enc_a     => enc_a,
      enc_b     => enc_b,
      io        => io,
      led_error => led_error
    );

end architecture rtl;
