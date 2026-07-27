--------------------------------------------------------------------------------
-- can_motor_max10.vhd
--
-- Wrapper di top level della variante MOTORE per il target Intel MAX 10
-- (10M08SAE144C8G, 50 MHz). Pilota 8 driver full-bridge VNH7100AS.
--   BRP = 5          -> 500 kbit/s con clock 50 MHz (20 Tq/bit, sample 80%)
--   MS_TICKS = 50000 -> base tempi di 1 ms a 50 MHz
--   PWM_PRESCALE=40  -> PWM ~19,5 kHz (50 MHz / (40 * 64))
--
-- ADC (MultiSense) abilitato: per letture reali di corrente occorre generare in
-- Quartus l'IP "Altera Modular ADC Core" + PLL e collegare adc_reader ad adc_val
-- (vedi rtl/adc_reader.vhd). Senza IP la sintesi resta valida: adc_val = 0
-- (telemetria a zero, nessun falso allarme perche' le soglie sono a fondo scala).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity can_motor_max10 is
  port (
    clk       : in    std_logic;                       -- 50 MHz (oscillatore del kit)
    rst_n     : in    std_logic;
    can_rxd   : in    std_logic;
    can_txd   : out   std_logic;
    node_addr : in    std_logic_vector(3 downto 0);
    safe_ch1  : in    std_logic;
    safe_ch2  : in    std_logic;
    mot       : out   std_logic_vector(31 downto 0);   -- INA/INB/PWM/SEL0 verso i VNH7100AS
    led_error : out   std_logic;                        -- fault bus CAN
    led_alarm : out   std_logic                         -- sovracorrente motori
  );
end entity can_motor_max10;

architecture rtl of can_motor_max10 is
  -- Correnti MultiSense: collegare adc_reader.adc_val qui dopo aver generato l'IP ADC.
  signal adc_val : std_logic_vector(127 downto 0) := (others => '0');
begin

  u_top : entity work.can_motor_top
    generic map (
      BRP          => 5,        -- 500 kbit/s con clock 50 MHz
      TSEG1        => 15,
      TSEG2        => 4,
      SJW          => 3,
      MS_TICKS     => 50000,    -- 1 ms @ 50 MHz
      TELEM_MS     => 10,       -- telemetria correnti ogni 10 ms (0 = off)
      PWM_PRESCALE => 40,       -- ~19,5 kHz
      ADC_PRESENT  => true
    )
    port map (
      clk       => clk,
      rst_n     => rst_n,
      can_rxd   => can_rxd,
      can_txd   => can_txd,
      node_addr => node_addr,
      safe_ch1  => safe_ch1,
      safe_ch2  => safe_ch2,
      adc_val   => adc_val,
      mot       => mot,
      led_error => led_error,
      led_alarm => led_alarm
    );

end architecture rtl;
