--------------------------------------------------------------------------------
-- tb_can_ioexpander.vhd
--
-- Testbench end-to-end:
--   * un nodo "host" (can_controller) invia trame CONFIG / OUTPUT / REQUEST
--   * il DUT (can_ioexpander_top) le riceve, pilota i pin e invia lo STATUS
--   * i due nodi condividono un bus CAN modellato in wired-AND ('0' dominante,
--     'H' recessivo tramite pull-up).
--
-- Scenario:
--   1. CONFIG : pin 31..16 = uscite, pin 15..0 = ingressi
--   2. OUTPUT : scrive 0xBEEF sui pin di uscita (parte alta)
--   3. verifica che io(31..16) = 0xBEEF
--   4. forza un ingresso (io(0)=1) -> il DUT invia STATUS automaticamente
--   5. verifica che l'host riceva lo stato aggiornato
--
-- Simulazione (GHDL):  vedere sim/run_ghdl.sh
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_can_ioexpander is
end entity tb_can_ioexpander;

architecture sim of tb_can_ioexpander is

  -- 20 MHz -> periodo 50 ns
  constant CLK_PERIOD : time := 50 ns;
  constant BIT_TIME   : time := 2 us;   -- 500 kbit/s

  signal clk    : std_logic := '0';
  signal rst_n  : std_logic := '0';
  signal sim_end: boolean   := false;

  -- bus CAN condiviso
  signal canbus : std_logic;
  signal a_txd, b_txd : std_logic;
  signal a_rxd, b_rxd : std_logic;

  -- interfaccia host (nodo A)
  signal h_txreq  : std_logic := '0';
  signal h_txid   : std_logic_vector(10 downto 0) := (others => '0');
  signal h_txrtr  : std_logic := '0';
  signal h_txdlc  : std_logic_vector(3 downto 0)  := (others => '0');
  signal h_txdata : std_logic_vector(63 downto 0) := (others => '0');
  signal h_txbusy : std_logic;
  signal h_txdone : std_logic;
  signal h_rxvld  : std_logic;
  signal h_rxid   : std_logic_vector(10 downto 0);
  signal h_rxrtr  : std_logic;
  signal h_rxdlc  : std_logic_vector(3 downto 0);
  signal h_rxdata : std_logic_vector(63 downto 0);
  signal h_err    : std_logic;
  signal h_errp   : std_logic;
  signal h_busoff : std_logic;
  signal h_tec    : std_logic_vector(7 downto 0);

  -- iniezione errore / diagnostica
  signal force_dom : std_logic := '0';   -- forza il bus a dominante
  signal seen_err  : std_logic := '0';   -- latch: errore rilevato

  -- DUT (nodo B)
  signal node_addr : std_logic_vector(3 downto 0) := "0001";
  signal io        : std_logic_vector(31 downto 0);
  signal tb_io_drv : std_logic_vector(31 downto 0) := (others => 'Z');
  signal led_err   : std_logic;

  -- identificatori
  constant ID_CONFIG : std_logic_vector(10 downto 0) := "010" & "0001" & "0000";
  constant ID_OUTPUT : std_logic_vector(10 downto 0) := "001" & "0001" & "0000";
  constant ID_STATUS : std_logic_vector(10 downto 0) := "100" & "0001" & "0000";

begin

  ----------------------------------------------------------------------------
  -- Clock
  ----------------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD/2 when not sim_end else '0';

  ----------------------------------------------------------------------------
  -- Bus CAN in wired-AND: dominante '0' prevale, altrimenti pull-up 'H'.
  ----------------------------------------------------------------------------
  canbus <= 'H';
  canbus <= '0' when a_txd = '0' else 'Z';
  canbus <= '0' when b_txd = '0' else 'Z';
  canbus <= '0' when force_dom = '1' else 'Z';   -- iniezione errore
  a_rxd  <= to_x01(canbus);
  b_rxd  <= to_x01(canbus);

  -- pilotaggio dei pin dal testbench (solo gli ingressi del DUT)
  io <= tb_io_drv;
  -- pull-down debole: i pin non pilotati si leggono come '0' (evita 'X')
  io <= (others => 'L');

  ----------------------------------------------------------------------------
  -- Nodo A: host
  ----------------------------------------------------------------------------
  u_host : entity work.can_controller
    port map (
      clk        => clk,
      rst_n      => rst_n,
      can_rx     => a_rxd,
      can_tx     => a_txd,
      tx_request => h_txreq,
      tx_id      => h_txid,
      tx_rtr     => h_txrtr,
      tx_dlc     => h_txdlc,
      tx_data    => h_txdata,
      tx_busy    => h_txbusy,
      tx_done    => h_txdone,
      rx_valid   => h_rxvld,
      rx_id      => h_rxid,
      rx_rtr     => h_rxrtr,
      rx_dlc     => h_rxdlc,
      rx_data    => h_rxdata,
      error_flag    => h_err,
      error_passive => h_errp,
      bus_off       => h_busoff,
      tec_value     => h_tec
    );

  -- latch dell'evento di errore rilevato dal nodo host
  errlatch : process (clk)
  begin
    if rising_edge(clk) then
      if h_err = '1' then
        seen_err <= '1';
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Nodo B: DUT (I/O expander)
  ----------------------------------------------------------------------------
  u_dut : entity work.can_ioexpander_top
    port map (
      clk       => clk,
      rst_n     => rst_n,
      can_rxd   => b_rxd,
      can_txd   => b_txd,
      node_addr => node_addr,
      io        => io,
      led_error => led_err
    );

  ----------------------------------------------------------------------------
  -- Stimoli
  ----------------------------------------------------------------------------
  stim : process

    -- invia una trama dal nodo host e attende l'ACK (tx_done)
    procedure host_send (id   : std_logic_vector(10 downto 0);
                         dlc  : std_logic_vector(3 downto 0);
                         data : std_logic_vector(63 downto 0)) is
    begin
      h_txid   <= id;
      h_txrtr  <= '0';
      h_txdlc  <= dlc;
      h_txdata <= data;
      h_txreq  <= '1';
      wait until h_txdone = '1' for 3 ms;
      assert h_txdone = '1'
        report "TIMEOUT: la trama host non e' stata confermata (ACK mancante)"
        severity failure;
      h_txreq <= '0';
      wait for 20 * BIT_TIME;   -- lascia passare EOF/IFS e tempo di idle
    end procedure;

  begin
    -- pin bassi (ingressi) pilotati a 0 dal testbench, pin alti in alta impedenza
    tb_io_drv <= (31 downto 16 => 'Z', others => '0');

    -- reset
    rst_n <= '0';
    wait for 10 * CLK_PERIOD;
    rst_n <= '1';
    wait for 20 * BIT_TIME;

    ------------------------------------------------------------------------
    -- 1) CONFIG: pin 31..16 uscite (dir=1), pin 15..0 ingressi (dir=0)
    ------------------------------------------------------------------------
    report "TB: invio CONFIG (dir = 0xFFFF0000)";
    host_send(ID_CONFIG, "0100", x"FFFF0000" & x"00000000");

    ------------------------------------------------------------------------
    -- 2) OUTPUT: scrive 0xBEEF sui pin alti
    ------------------------------------------------------------------------
    report "TB: invio OUTPUT (pin word = 0xBEEF0000)";
    host_send(ID_OUTPUT, "0100", x"BEEF0000" & x"00000000");
    wait for 5 * BIT_TIME;

    ------------------------------------------------------------------------
    -- 3) verifica delle uscite
    ------------------------------------------------------------------------
    assert to_x01(io(31 downto 16)) = x"BEEF"
      report "FAIL: uscite errate, atteso 0xBEEF, letto 0x" &
             to_hstring(to_x01(io(31 downto 16)))
      severity failure;
    report "TB: OK uscite = 0xBEEF";

    ------------------------------------------------------------------------
    -- 4) variazione ingresso -> STATUS automatico
    ------------------------------------------------------------------------
    report "TB: forzo io(0)=1, attendo STATUS dal DUT";
    tb_io_drv(0) <= '1';

    wait until h_rxvld = '1' for 3 ms;
    assert h_rxvld = '1'
      report "TIMEOUT: nessuno STATUS ricevuto dal DUT" severity failure;

    assert h_rxid = ID_STATUS
      report "FAIL: ID STATUS errato" severity failure;

    -- stato atteso: uscite 0xBEEF (parte alta) + ingresso pin0 = 1
    assert h_rxdata(63 downto 32) = x"BEEF0001"
      report "FAIL: STATUS errato, atteso 0xBEEF0001, letto 0x" &
             to_hstring(h_rxdata(63 downto 32))
      severity failure;
    report "TB: OK STATUS = 0xBEEF0001";

    ------------------------------------------------------------------------
    -- 5) iniezione bit/stuff error e verifica del recupero
    ------------------------------------------------------------------------
    report "TB: iniezione errore (bus forzato dominante per 8 bit)";
    force_dom <= '1';
    wait for 8 * BIT_TIME;
    force_dom <= '0';
    wait for 30 * BIT_TIME;         -- attende error frame + recupero a idle

    assert seen_err = '1'
      report "FAIL: l'errore iniettato non e' stato rilevato" severity failure;
    report "TB: OK errore rilevato dal MAC (error frame emesso)";

    -- recupero: una nuova trama deve essere trasmessa e applicata
    report "TB: verifica recupero post-errore (OUTPUT = 0x1234)";
    host_send(ID_OUTPUT, "0100", x"12340000" & x"00000000");
    wait for 5 * BIT_TIME;
    assert to_x01(io(31 downto 16)) = x"1234"
      report "FAIL: nessun recupero dopo l'errore, uscite = 0x" &
             to_hstring(to_x01(io(31 downto 16))) severity failure;
    report "TB: OK recupero dopo errore, uscite = 0x1234";

    report "TB: *** TUTTI I TEST SUPERATI ***" severity note;
    sim_end <= true;
    wait;
  end process;

end architecture sim;
