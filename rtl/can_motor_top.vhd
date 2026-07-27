--------------------------------------------------------------------------------
-- can_motor_top.vhd
--
-- Top level della variante "motor bridge": controller CAN 2.0A + livello
-- applicativo motore (motor_expander) per pilotare 8 driver full-bridge
-- STMicro VNH7100AS. Le 32 uscite mot[] sono le linee INA/INB/PWM/SEL0 dei
-- driver; le correnti MultiSense arrivano su adc_val (ADC del MAX 10).
--
-- Interfaccia fisica (verso un transceiver CAN, es. TJA1050 / SN65HVD230):
--   can_rxd : RXD del transceiver (0 = dominante)
--   can_txd : TXD verso il transceiver (0 = dominante)
--
-- node_addr : indirizzo del nodo (4 bit), da dip-switch/strapping.
-- safe_ch1/2: doppio canale di consenso; se manca -> stato sicuro configurabile
--             (coast o brake) su tutti i motori.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_motor_top is
  generic (
    -- bit timing (default: 20 MHz, 500 kbit/s)
    BRP   : positive := 2;
    TSEG1 : positive := 15;
    TSEG2 : positive := 4;
    SJW   : positive := 3;
    -- base tempi, telemetria e PWM
    MS_TICKS     : positive := 20000;  -- cicli di clk per 1 ms
    TELEM_MS     : natural  := 10;     -- periodo telemetria ADC (0 = off)
    PWM_PRESCALE : positive := 40;     -- divisore PWM (freq = f_clk/(PRESCALE*64))
    ADC_PRESENT  : boolean  := true    -- letture MultiSense via ADC (MAX 10)
  );
  port (
    clk       : in    std_logic;
    rst_n     : in    std_logic;

    can_rxd   : in    std_logic;
    can_txd   : out   std_logic;

    node_addr : in    std_logic_vector(3 downto 0);

    safe_ch1  : in    std_logic;
    safe_ch2  : in    std_logic;

    -- correnti MultiSense (8 canali a 16 bit); usato solo se ADC_PRESENT=true
    adc_val   : in    std_logic_vector(127 downto 0) := (others => '0');

    -- linee di controllo verso gli 8 VNH7100AS
    mot       : out   std_logic_vector(31 downto 0);

    led_error : out   std_logic;   -- fault bus CAN (error-passive / bus-off)
    led_alarm : out   std_logic    -- sovracorrente su almeno un motore
  );
end entity can_motor_top;

architecture rtl of can_motor_top is

  signal tx_request : std_logic;
  signal tx_id      : std_logic_vector(10 downto 0);
  signal tx_rtr     : std_logic;
  signal tx_dlc     : std_logic_vector(3 downto 0);
  signal tx_data    : std_logic_vector(63 downto 0);
  signal tx_busy    : std_logic;
  signal tx_done    : std_logic;

  signal rx_valid   : std_logic;
  signal rx_id      : std_logic_vector(10 downto 0);
  signal rx_rtr     : std_logic;
  signal rx_dlc     : std_logic_vector(3 downto 0);
  signal rx_data    : std_logic_vector(63 downto 0);

  signal err_passive : std_logic;
  signal bus_off     : std_logic;

begin

  -- LED acceso su fault persistente (error-passive o bus-off)
  led_error <= err_passive or bus_off;

  u_can : entity work.can_controller
    generic map (BRP => BRP, TSEG1 => TSEG1, TSEG2 => TSEG2, SJW => SJW)
    port map (
      clk        => clk,
      rst_n      => rst_n,
      can_rx     => can_rxd,
      can_tx     => can_txd,
      tx_request => tx_request,
      tx_id      => tx_id,
      tx_rtr     => tx_rtr,
      tx_dlc     => tx_dlc,
      tx_data    => tx_data,
      tx_busy    => tx_busy,
      tx_done    => tx_done,
      rx_valid   => rx_valid,
      rx_id      => rx_id,
      rx_rtr     => rx_rtr,
      rx_dlc     => rx_dlc,
      rx_data    => rx_data,
      error_flag    => open,
      error_passive => err_passive,
      bus_off       => bus_off,
      tec_value     => open
    );

  u_mot : entity work.motor_expander
    generic map (MS_TICKS => MS_TICKS, TELEM_MS => TELEM_MS,
                 PWM_PRESCALE => PWM_PRESCALE, ADC_PRESENT => ADC_PRESENT)
    port map (
      clk        => clk,
      rst_n      => rst_n,
      node_addr  => node_addr,
      safe_ch1   => safe_ch1,
      safe_ch2   => safe_ch2,
      rx_valid   => rx_valid,
      rx_id      => rx_id,
      rx_rtr     => rx_rtr,
      rx_dlc     => rx_dlc,
      rx_data    => rx_data,
      tx_request => tx_request,
      tx_id      => tx_id,
      tx_rtr     => tx_rtr,
      tx_dlc     => tx_dlc,
      tx_data    => tx_data,
      tx_busy    => tx_busy,
      tx_done    => tx_done,
      adc_val    => adc_val,
      mot        => mot,
      led_alarm  => led_alarm
    );

end architecture rtl;
