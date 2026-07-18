--------------------------------------------------------------------------------
-- can_ioexpander_top.vhd
--
-- Top level dell'I/O expander su CAN bus.
-- Collega il controller CAN 2.0A all'espansore di I/O a 32 pin bidirezionali.
--
-- Interfaccia fisica (verso un transceiver CAN, es. TJA1050 / SN65HVD230):
--   can_rxd : RXD del transceiver (0 = dominante)
--   can_txd : TXD verso il transceiver (0 = dominante)
--
-- node_addr : indirizzo del nodo (4 bit), tipicamente da dip-switch/strapping.
--
-- Esempio di pinout (da adattare al proprio dispositivo nel file di vincoli):
--   clk       -> oscillatore 20 MHz
--   rst_n     -> reset attivo basso
--   can_rxd   -> RXD transceiver
--   can_txd   -> TXD transceiver
--   node_addr -> 4 dip-switch
--   io[31:0]  -> 32 pin di I/O
--   led_error -> LED diagnostico (acceso su errore CAN)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_ioexpander_top is
  generic (
    -- bit timing (default: 20 MHz, 500 kbit/s)
    BRP   : positive := 2;
    TSEG1 : positive := 15;
    TSEG2 : positive := 4;
    SJW   : positive := 3
  );
  port (
    clk       : in    std_logic;
    rst_n     : in    std_logic;

    can_rxd   : in    std_logic;
    can_txd   : out   std_logic;

    node_addr : in    std_logic_vector(3 downto 0);
    io        : inout std_logic_vector(31 downto 0);

    led_error : out   std_logic
  );
end entity can_ioexpander_top;

architecture rtl of can_ioexpander_top is

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

  signal err        : std_logic;

begin

  led_error <= err;

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
      error_flag => err
    );

  u_io : entity work.io_expander
    port map (
      clk        => clk,
      rst_n      => rst_n,
      node_addr  => node_addr,
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
      io         => io
    );

end architecture rtl;
