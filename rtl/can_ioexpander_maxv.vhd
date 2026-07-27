--------------------------------------------------------------------------------
-- can_ioexpander_maxv.vhd
--
-- Wrapper di top level per il target MAX V (5M1270ZT144, 20 MHz).
-- Istanzia can_ioexpander_top SENZA ADC (ADC_PRESENT=false): il MAX V e' un CPLD
-- puramente digitale, non ha ingressi analogici. adc_val e' lasciato a 0.
-- Le porte esterne sono identiche al pinout MAX V esistente (nessun pin analog).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity can_ioexpander_maxv is
  port (
    clk       : in    std_logic;                       -- 20 MHz
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
end entity can_ioexpander_maxv;

architecture rtl of can_ioexpander_maxv is
begin

  u_top : entity work.can_ioexpander_top
    generic map (
      BRP           => 2,       -- 500 kbit/s con clock 20 MHz
      TSEG1         => 15,
      TSEG2         => 4,
      SJW           => 3,
      MS_TICKS      => 20000,   -- 1 ms @ 20 MHz
      ENC_PERIOD_MS => 10,
      ADC_PRESENT   => false    -- nessun ADC sul MAX V
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
      -- adc_val: default (0), non usato
      io        => io,
      led_error => led_error
    );

end architecture rtl;
