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
    SJW   : positive := 3;
    -- encoder: base tempi e periodo di trasmissione
    MS_TICKS      : positive := 20000;  -- cicli di clk per 1 ms (20 MHz)
    ENC_PERIOD_MS : natural  := 10      -- periodo TX conteggi encoder (0 = off)
  );
  port (
    clk       : in    std_logic;
    rst_n     : in    std_logic;

    can_rxd   : in    std_logic;
    can_txd   : out   std_logic;

    node_addr : in    std_logic_vector(3 downto 0);

    -- funzione di sicurezza: due canali di consenso attivi-alti.
    -- Se uno qualsiasi va basso, le uscite sono forzate a livello basso.
    safe_ch1  : in    std_logic;
    safe_ch2  : in    std_logic;

    -- 8 encoder incrementali in quadratura (canali A/B)
    enc_a     : in    std_logic_vector(7 downto 0);
    enc_b     : in    std_logic_vector(7 downto 0);

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

  signal err_passive  : std_logic;
  signal bus_off      : std_logic;

  signal enc_count    : std_logic_vector(127 downto 0);
  signal enc_rst      : std_logic_vector(7 downto 0);

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

  -- 8 decodificatori di quadratura, uno per encoder
  gen_enc : for i in 0 to 7 generate
    u_enc : entity work.quad_decoder
      port map (
        clk       => clk,
        rst_n     => rst_n,
        a         => enc_a(i),
        b         => enc_b(i),
        rst_count => enc_rst(i),
        count     => enc_count(16*i+15 downto 16*i)
      );
  end generate;

  u_io : entity work.io_expander
    generic map (MS_TICKS => MS_TICKS, ENC_PERIOD_MS => ENC_PERIOD_MS)
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
      enc_count  => enc_count,
      enc_rst    => enc_rst,
      io         => io
    );

end architecture rtl;
