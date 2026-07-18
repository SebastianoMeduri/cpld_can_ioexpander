--------------------------------------------------------------------------------
-- can_controller.vhd
--
-- Controller CAN 2.0A completo: sincronizzatore di ingresso + bit timing + MAC.
-- Espone un'interfaccia a messaggi (una trama per volta) verso l'applicazione.
--
-- can_rx : livello RXD dal transceiver CAN (0 = dominante)
-- can_tx : livello TXD verso il transceiver CAN (0 = dominante)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_controller is
  generic (
    BRP   : positive := 2;
    TSEG1 : positive := 15;
    TSEG2 : positive := 4;
    SJW   : positive := 3
  );
  port (
    clk        : in  std_logic;
    rst_n      : in  std_logic;

    can_rx     : in  std_logic;
    can_tx     : out std_logic;

    -- trasmissione
    tx_request : in  std_logic;
    tx_id      : in  std_logic_vector(10 downto 0);
    tx_rtr     : in  std_logic;
    tx_dlc     : in  std_logic_vector(3 downto 0);
    tx_data    : in  std_logic_vector(63 downto 0);
    tx_busy    : out std_logic;
    tx_done    : out std_logic;

    -- ricezione
    rx_valid   : out std_logic;
    rx_id      : out std_logic_vector(10 downto 0);
    rx_rtr     : out std_logic;
    rx_dlc     : out std_logic_vector(3 downto 0);
    rx_data    : out std_logic_vector(63 downto 0);

    -- stato / diagnostica
    error_flag    : out std_logic;
    error_passive : out std_logic;
    bus_off       : out std_logic;
    tec_value     : out std_logic_vector(7 downto 0)
  );
end entity can_controller;

architecture rtl of can_controller is

  signal rx_meta : std_logic := '1';   -- sincronizzatore 2FF, stadio 1
  signal rx_sync : std_logic := '1';   -- sincronizzatore 2FF, stadio 2
  signal s_sample: std_logic;
  signal s_txpt  : std_logic;
  signal s_idle  : std_logic;

begin

  -- Sincronizzatore a 2 flip-flop del segnale di bus in ingresso.
  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        rx_meta <= '1';
        rx_sync <= '1';
      else
        rx_meta <= can_rx;
        rx_sync <= rx_meta;
      end if;
    end if;
  end process;

  u_timing : entity work.can_bit_timing
    generic map (BRP => BRP, TSEG1 => TSEG1, TSEG2 => TSEG2, SJW => SJW)
    port map (
      clk          => clk,
      rst_n        => rst_n,
      rx_sync      => rx_sync,
      bus_idle     => s_idle,
      sample_point => s_sample,
      tx_point     => s_txpt
    );

  u_mac : entity work.can_mac
    port map (
      clk          => clk,
      rst_n        => rst_n,
      sample_point => s_sample,
      tx_point     => s_txpt,
      rx_sync      => rx_sync,
      can_tx       => can_tx,
      bus_idle     => s_idle,
      tx_request   => tx_request,
      tx_id        => tx_id,
      tx_rtr       => tx_rtr,
      tx_dlc       => tx_dlc,
      tx_data      => tx_data,
      tx_busy      => tx_busy,
      tx_done      => tx_done,
      rx_valid     => rx_valid,
      rx_id        => rx_id,
      rx_rtr       => rx_rtr,
      rx_dlc       => rx_dlc,
      rx_data      => rx_data,
      error_flag    => error_flag,
      error_passive => error_passive,
      bus_off       => bus_off,
      tec_value     => tec_value
    );

end architecture rtl;
