--------------------------------------------------------------------------------
-- tb_can_motor.vhd
--
-- Testbench della variante MOTORE (can_motor_top, 8 driver VNH7100AS):
--   * un nodo "host" (can_controller) invia MOTOR / CONFIG / PERIOD / REQUEST;
--   * il DUT pilota le linee INA/INB/PWM/SEL0 e invia STATUS / ANALOG;
--   * bus CAN modellato in wired-AND ('0' dominante).
--
-- Scenari: comando direzione+duty (con fondoscala = ON statico), stato sicuro
-- configurabile (coast/brake), STATUS, telemetria correnti e bitmap sovracorrente.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.can_pkg.all;

entity tb_can_motor is
end entity tb_can_motor;

architecture sim of tb_can_motor is

  constant CLK_PERIOD : time := 50 ns;   -- 20 MHz
  constant BIT_TIME   : time := 2 us;    -- 500 kbit/s

  signal clk    : std_logic := '0';
  signal rst_n  : std_logic := '0';
  signal sim_end: boolean   := false;

  signal canbus : std_logic;
  signal a_txd, b_txd : std_logic;
  signal a_rxd, b_rxd : std_logic;

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

  -- DUT
  signal node_addr : std_logic_vector(3 downto 0) := "0001";
  signal safe_ch1  : std_logic := '1';
  signal safe_ch2  : std_logic := '1';
  -- correnti MultiSense di test: ch0=0x0AAA, ch1=0x0555, resto 0
  signal adc_val   : std_logic_vector(127 downto 0) :=
      x"00000000000000000000000005550AAA";
  signal mot       : std_logic_vector(31 downto 0);
  signal led_err   : std_logic;
  signal led_alm   : std_logic;

  -- identificatori (NODE = 0001)
  constant ID_MOTOR  : std_logic_vector(10 downto 0) := "001" & "0001" & "0000";
  constant ID_CFG0   : std_logic_vector(10 downto 0) := "010" & "0001" & "0000";
  constant ID_THR0   : std_logic_vector(10 downto 0) := "010" & "0001" & "0001";
  constant ID_THR1   : std_logic_vector(10 downto 0) := "010" & "0001" & "0010";
  constant ID_REQ    : std_logic_vector(10 downto 0) := "011" & "0001" & "0000";
  constant ID_STATUS : std_logic_vector(10 downto 0) := "100" & "0001" & "0000";
  constant ID_PERIOD : std_logic_vector(10 downto 0) := "000" & "0001" & "0000";
  constant ID_ANA0   : std_logic_vector(10 downto 0) := "111" & "0001" & "0000";
  constant ID_ACMP   : std_logic_vector(10 downto 0) := "111" & "0001" & "0010";

begin

  clk <= not clk after CLK_PERIOD/2 when not sim_end else '0';

  canbus <= 'H';
  canbus <= '0' when a_txd = '0' else 'Z';
  canbus <= '0' when b_txd = '0' else 'Z';
  a_rxd  <= to_x01(canbus);
  b_rxd  <= to_x01(canbus);

  u_host : entity work.can_controller
    port map (
      clk => clk, rst_n => rst_n, can_rx => a_rxd, can_tx => a_txd,
      tx_request => h_txreq, tx_id => h_txid, tx_rtr => h_txrtr,
      tx_dlc => h_txdlc, tx_data => h_txdata, tx_busy => h_txbusy, tx_done => h_txdone,
      rx_valid => h_rxvld, rx_id => h_rxid, rx_rtr => h_rxrtr,
      rx_dlc => h_rxdlc, rx_data => h_rxdata,
      error_flag => h_err, error_passive => h_errp, bus_off => h_busoff, tec_value => h_tec
    );

  u_dut : entity work.can_motor_top
    generic map (BRP => 2, MS_TICKS => 20, TELEM_MS => 0,
                 PWM_PRESCALE => 2, ADC_PRESENT => true)
    port map (
      clk => clk, rst_n => rst_n, can_rxd => b_rxd, can_txd => b_txd,
      node_addr => node_addr, safe_ch1 => safe_ch1, safe_ch2 => safe_ch2,
      adc_val => adc_val, mot => mot, led_error => led_err, led_alarm => led_alm
    );

  stim : process

    procedure host_send (id   : std_logic_vector(10 downto 0);
                         dlc  : std_logic_vector(3 downto 0);
                         data : std_logic_vector(63 downto 0)) is
    begin
      h_txid <= id; h_txrtr <= '0'; h_txdlc <= dlc; h_txdata <= data; h_txreq <= '1';
      wait until h_txdone = '1' for 3 ms;
      assert h_txdone = '1'
        report "TIMEOUT: trama host non confermata (ACK mancante)" severity failure;
      h_txreq <= '0';
      wait for 20 * BIT_TIME;
    end procedure;

    procedure wait_for (id : std_logic_vector(10 downto 0);
                        rxd : out std_logic_vector(63 downto 0)) is
      variable got : boolean := false;
    begin
      while not got loop
        wait until h_rxvld = '1' for 4 ms;
        assert h_rxvld = '1' report "TIMEOUT: trama attesa non ricevuta" severity failure;
        if h_rxid = id then rxd := h_rxdata; got := true; end if;
        wait for CLK_PERIOD;
      end loop;
    end procedure;

    variable rxd : std_logic_vector(63 downto 0);

  begin
    rst_n <= '0';
    wait for 10 * CLK_PERIOD;
    rst_n <= '1';
    wait for 20 * BIT_TIME;

    ------------------------------------------------------------------------
    -- 1) MOTOR: motore0 AVANTI a fondoscala (ON statico), motore1 INDIETRO
    --    duty medio, gli altri in coast.
    --    byte0 = 0x7F (mode=01 fwd, duty=0x3F fondoscala)
    --    byte1 = 0xA0 (mode=10 rev, duty=0x20)
    ------------------------------------------------------------------------
    report "TB: MOTOR - motore0 FWD fondoscala, motore1 REV duty 0x20";
    host_send(ID_MOTOR, "1000", x"7FA0000000000000");
    wait for 5 * BIT_TIME;

    assert mot(0) = '1' and mot(8) = '0' and mot(16) = '1'
      report "FAIL: motore0 - atteso INA=1 INB=0 PWM=1 (fondoscala)" severity failure;
    assert mot(1) = '0' and mot(9) = '1'
      report "FAIL: motore1 - atteso INA=0 INB=1 (reverse)" severity failure;
    assert mot(2) = '0' and mot(10) = '0' and mot(18) = '0'
      report "FAIL: motore2 - atteso coast (tutto 0)" severity failure;
    assert mot(24) = '0'
      report "FAIL: SEL0 atteso 0 (default)" severity failure;
    report "TB: OK comando MOTOR (direzione + fondoscala ON)";

    ------------------------------------------------------------------------
    -- 2) STATUS su richiesta: byte0 bit0 = safe_ok (deve essere 1)
    ------------------------------------------------------------------------
    report "TB: REQUEST -> STATUS";
    host_send(ID_REQ, "0000", (others => '0'));
    wait_for(ID_STATUS, rxd);
    assert rxd(56) = '1'
      report "FAIL: STATUS safe_ok atteso 1" severity failure;
    report "TB: OK STATUS (safe_ok=1)";

    ------------------------------------------------------------------------
    -- 3) Sicurezza in modalita' COAST (default): consenso giu' -> tutto 0
    ------------------------------------------------------------------------
    report "TB: sicurezza COAST - safe_ch1=0";
    safe_ch1 <= '0';
    wait for 12 * CLK_PERIOD;
    assert mot(0) = '0' and mot(8) = '0' and mot(16) = '0'
      report "FAIL: coast di sicurezza non applicato (atteso tutto 0)" severity failure;
    report "TB: OK stato sicuro COAST (uscite a 0)";
    safe_ch1 <= '1';
    wait for 12 * CLK_PERIOD;
    assert mot(16) = '1'
      report "FAIL: nessun ripristino dopo COAST (PWM0 atteso 1)" severity failure;
    report "TB: OK ripristino motore0 (PWM fondoscala)";

    ------------------------------------------------------------------------
    -- 4) Configura stato sicuro = BRAKE, poi consenso giu' -> INA=INB=0, PWM=1
    ------------------------------------------------------------------------
    report "TB: CONFIG stato sicuro = BRAKE (byte0 bit0 = 1)";
    host_send(ID_CFG0, "0001", x"0100000000000000");
    safe_ch1 <= '0';
    wait for 12 * CLK_PERIOD;
    assert mot(0) = '0' and mot(8) = '0' and mot(16) = '1'
      report "FAIL: brake di sicurezza non applicato (atteso INA=INB=0, PWM=1)" severity failure;
    report "TB: OK stato sicuro BRAKE (frenata a GND)";
    safe_ch1 <= '1';
    wait for 12 * CLK_PERIOD;

    ------------------------------------------------------------------------
    -- 5) Telemetria correnti (ANALOG) e bitmap sovracorrente
    ------------------------------------------------------------------------
    report "TB: abilito telemetria correnti (PERIOD)";
    host_send(ID_PERIOD, "0100", x"0064000000000000");   -- periodo 100 (ms fittizi)

    report "TB: attendo trama ANALOG (correnti ch0..3)";
    wait_for(ID_ANA0, rxd);
    assert rxd(63 downto 48) = x"0AAA" and rxd(47 downto 32) = x"0555"
      report "FAIL: correnti errate, atteso ch0=0x0AAA ch1=0x0555" severity failure;
    report "TB: OK telemetria correnti via CAN";

    report "TB: imposto soglie sovracorrente (CONFIG SUB=1/2)";
    host_send(ID_THR0, "1000", x"0500" & x"0800" & x"0001" & x"0001"); -- m0..3
    host_send(ID_THR1, "1000", x"0001" & x"0001" & x"0001" & x"0001"); -- m4..7

    report "TB: attendo bitmap sovracorrente (ANALOG SUB=2)";
    wait_for(ID_ACMP, rxd);
    assert rxd(63 downto 56) = x"01"
      report "FAIL: bitmap sovracorrente errato, atteso 0x01 (solo motore0)" severity failure;
    report "TB: OK bitmap sovracorrente = 0x01 (motore0 sopra soglia)";

    -- il LED allarme deve seguire l'OR del bitmap (motore0 in sovracorrente)
    wait for 2 * CLK_PERIOD;
    assert led_alm = '1'
      report "FAIL: led_alarm atteso 1 con motore0 in sovracorrente" severity failure;
    report "TB: OK led_alarm acceso su sovracorrente";

    report "TB: *** TUTTI I TEST SUPERATI ***" severity note;
    sim_end <= true;
    wait;
  end process;

end architecture sim;
