--------------------------------------------------------------------------------
-- motor_expander.vhd
--
-- Livello applicativo specializzato per pilotare 8 driver full-bridge
-- STMicro VNH7100AS via CAN. Ogni driver usa 4 linee di controllo digitali
-- (INA, INB, PWM, SEL0) e restituisce la corrente/diagnostica su MultiSense
-- (letta dall'ADC del MAX 10). Le 32 uscite mappano gli 8 driver:
--
--   mot(7..0)   = INA(0..7)     (direzione A)
--   mot(15..8)  = INB(0..7)     (direzione B)
--   mot(23..16) = PWM(0..7)     (modulazione)
--   mot(31..24) = SEL0(0..7)    (selezione MultiSense, valore comune configurabile)
--
-- Comando per motore (mode a 2 bit + PWM a 6 bit):
--   mode "00" COAST : ponte in alta impedenza (INA=INB=0, PWM=0)
--   mode "01" FWD   : INA=1, INB=0, PWM=duty
--   mode "10" REV   : INA=0, INB=1, PWM=duty
--   mode "11" BRAKE : frenata a GND (INA=INB=0, PWM=1)
--   duty a fondoscala (0x3F) -> PWM statico alto = controllo ON/OFF.
--
-- Identificatori (11 bit) = FUNC(3) & NODE_ADDR(4) & SUB(4):
--   FUNC="000" PERIOD   (host->exp): data[63:48] = periodo telemetria ADC in ms
--   FUNC="001" MOTOR    (host->exp): 8 byte, byte k = motore k [7:6]=mode [5:0]=duty
--   FUNC="010" CONFIG   (host->exp): SUB=0 -> byte0 bit0=safe_mode (0=coast,1=brake),
--                                    bit1=SEL0; SUB=1 -> soglie corrente motori 0..3;
--                                    SUB=2 -> soglie corrente motori 4..7 (uint16 12 bit)
--   FUNC="011" REQUEST  (host->exp): invio immediato dello STATUS
--   FUNC="100" STATUS   (exp->host): byte0 bit0=safe_ok, bit1=safe_mode, bit2=SEL0;
--                                    byte1 = bitmap sovracorrente (bit i = motore i)
--   FUNC="111" ANALOG   (exp->host): correnti MultiSense (SUB=0 ch0..3, SUB=1 ch4..7,
--                                    4 x uint16 12 bit); SUB=2 -> bitmap sovracorrente
--                                    (data[63:56]), inviato al variare e in coda.
--
-- SICUREZZA (doppio canale fail-safe): se manca il consenso (safe_ch1/2) tutti i
-- motori vanno allo stato sicuro CONFIGURABILE: coast (default) o brake a GND.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity motor_expander is
  generic (
    MS_TICKS       : positive := 50000;  -- cicli di clk per 1 ms (50 MHz -> 50000)
    TELEM_MS       : natural  := 10;     -- periodo telemetria ADC di default (0 = off)
    PWM_PRESCALE   : positive := 40;     -- divisore PWM (50 MHz,6 bit -> ~19,5 kHz)
    ADC_PRESENT    : boolean  := true    -- letture MultiSense via ADC (MAX 10)
  );
  port (
    clk        : in    std_logic;
    rst_n      : in    std_logic;
    node_addr  : in    std_logic_vector(3 downto 0);

    -- funzione di sicurezza: due canali di consenso attivi-alti
    safe_ch1   : in    std_logic;
    safe_ch2   : in    std_logic;

    -- verso il controller CAN (lato ricezione)
    rx_valid   : in    std_logic;
    rx_id      : in    std_logic_vector(10 downto 0);
    rx_rtr     : in    std_logic;
    rx_dlc     : in    std_logic_vector(3 downto 0);
    rx_data    : in    std_logic_vector(63 downto 0);

    -- verso il controller CAN (lato trasmissione)
    tx_request : out   std_logic;
    tx_id      : out   std_logic_vector(10 downto 0);
    tx_rtr     : out   std_logic;
    tx_dlc     : out   std_logic_vector(3 downto 0);
    tx_data    : out   std_logic_vector(63 downto 0);
    tx_busy    : in    std_logic;
    tx_done    : in    std_logic;

    -- ADC: 8 canali a 16 bit (canale i = bit 16*i+15 .. 16*i; valore su 12 bit)
    adc_val    : in    std_logic_vector(127 downto 0) := (others => '0');

    -- linee di controllo verso gli 8 VNH7100AS (uscite)
    mot        : out   std_logic_vector(31 downto 0);

    -- allarme motori: alto se almeno un canale e' in sovracorrente
    led_alarm  : out   std_logic
  );
end entity motor_expander;

architecture rtl of motor_expander is

  constant FUNC_PERIOD  : std_logic_vector(2 downto 0) := "000";
  constant FUNC_MOTOR   : std_logic_vector(2 downto 0) := "001";
  constant FUNC_CONFIG  : std_logic_vector(2 downto 0) := "010";
  constant FUNC_REQUEST : std_logic_vector(2 downto 0) := "011";
  constant FUNC_STATUS  : std_logic_vector(2 downto 0) := "100";
  constant FUNC_ANALOG  : std_logic_vector(2 downto 0) := "111";

  type job_t is (JOB_NONE, JOB_STATUS, JOB_ANA0, JOB_ANA1, JOB_ACMP);

  type mode_arr_t is array(0 to 7) of std_logic_vector(1 downto 0);
  type duty_arr_t is array(0 to 7) of unsigned(5 downto 0);

  signal mode_r : mode_arr_t := (others => "00");
  signal duty_r : duty_arr_t := (others => (others => '0'));

  signal pwm_out  : std_logic_vector(7 downto 0);
  signal ina, inb, pwmd : std_logic_vector(7 downto 0);

  signal safe_mode : std_logic := '0';   -- 0 = coast, 1 = brake (stato sicuro)
  signal sel0_cfg  : std_logic := '0';   -- valore comune SEL0

  -- funzione di sicurezza (2FF)
  signal sf1a, sf1b : std_logic := '0';
  signal sf2a, sf2b : std_logic := '0';
  signal safe_ok    : std_logic := '0';
  signal safe_ok_d  : std_logic := '0';

  -- trasmissione
  signal pending_status : std_logic := '0';
  signal cur_job        : job_t := JOB_NONE;
  signal txreq          : std_logic := '0';
  signal txid_r         : std_logic_vector(10 downto 0) := (others => '0');
  signal txdata_r       : std_logic_vector(63 downto 0) := (others => '0');
  signal txdlc_r        : std_logic_vector(3 downto 0)  := "0010";

  -- timer periodico telemetria
  signal telem_period : unsigned(15 downto 0) := to_unsigned(TELEM_MS, 16);
  signal ms_presc     : integer range 0 to MS_TICKS-1 := 0;
  signal ms_cnt       : unsigned(15 downto 0) := (others => '0');
  signal ana_phase    : integer range 0 to 2 := 0;   -- 0=idle,1=blk0,2=blk1
  signal ana_blk0     : std_logic_vector(63 downto 0);
  signal ana_blk1     : std_logic_vector(63 downto 0);

  -- soglie di corrente (8 x 16 bit, come adc_val) e confronto adc >= soglia
  signal thr         : std_logic_vector(127 downto 0) := (others => '1');
  signal cmp         : std_logic_vector(7 downto 0);
  signal cmp_d       : std_logic_vector(7 downto 0) := (others => '0');
  signal pending_cmp : std_logic := '0';

  signal flags_byte  : std_logic_vector(7 downto 0);

begin

  ----------------------------------------------------------------------------
  -- Generatori PWM (uno per motore)
  ----------------------------------------------------------------------------
  gpwm : for i in 0 to 7 generate
    u_pwm : entity work.pwm_gen
      generic map (DUTY_BITS => 6, PRESCALE => PWM_PRESCALE)
      port map (clk => clk, rst_n => rst_n, duty => duty_r(i), pwm => pwm_out(i));
  end generate;

  ----------------------------------------------------------------------------
  -- Pilotaggio dei driver (combinatorio). Stato sicuro configurabile.
  ----------------------------------------------------------------------------
  drive : process (mode_r, pwm_out, safe_ok, safe_mode)
  begin
    for i in 0 to 7 loop
      if safe_ok = '0' then
        if safe_mode = '1' then          -- BRAKE a GND
          ina(i) <= '0'; inb(i) <= '0'; pwmd(i) <= '1';
        else                             -- COAST (alta impedenza)
          ina(i) <= '0'; inb(i) <= '0'; pwmd(i) <= '0';
        end if;
      else
        case mode_r(i) is
          when "01"   => ina(i) <= '1'; inb(i) <= '0'; pwmd(i) <= pwm_out(i);  -- FWD
          when "10"   => ina(i) <= '0'; inb(i) <= '1'; pwmd(i) <= pwm_out(i);  -- REV
          when "11"   => ina(i) <= '0'; inb(i) <= '0'; pwmd(i) <= '1';          -- BRAKE
          when others => ina(i) <= '0'; inb(i) <= '0'; pwmd(i) <= '0';          -- COAST
        end case;
      end if;
    end loop;
  end process;

  mot(7 downto 0)   <= ina;
  mot(15 downto 8)  <= inb;
  mot(23 downto 16) <= pwmd;
  mot(31 downto 24) <= (others => sel0_cfg);

  -- allarme motori = OR del bitmap di sovracorrente (a riposo se ADC assente)
  led_alarm <= '1' when cmp /= "00000000" else '0';

  -- payload ADC (MultiSense): 4 x uint16, canale piu' basso nei byte piu' alti
  ana_blk0 <= adc_val(15 downto 0)  & adc_val(31 downto 16) &
              adc_val(47 downto 32) & adc_val(63 downto 48);
  ana_blk1 <= adc_val(79 downto 64)   & adc_val(95 downto 80) &
              adc_val(111 downto 96)  & adc_val(127 downto 112);

  -- confronto sovracorrente per canale (12 bit utili); a riposo se ADC assente
  gen_cmp_on : if ADC_PRESENT generate
    gc : for i in 0 to 7 generate
      cmp(i) <= '1' when unsigned(adc_val(16*i+11 downto 16*i)) >=
                         unsigned(thr(16*i+11 downto 16*i)) else '0';
    end generate;
  end generate;
  gen_cmp_off : if not ADC_PRESENT generate
    cmp <= (others => '0');
  end generate;

  flags_byte <= "00000" & sel0_cfg & safe_mode & safe_ok;

  -- uscite verso il controller
  tx_request <= txreq;
  tx_id      <= txid_r;
  tx_rtr     <= '0';
  tx_dlc     <= txdlc_r;
  tx_data    <= txdata_r;

  process (clk)
    variable b : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        mode_r <= (others => "00");
        duty_r <= (others => (others => '0'));
        safe_mode <= '0';
        sel0_cfg  <= '0';
        pending_status <= '0';
        cur_job  <= JOB_NONE;
        txreq    <= '0';
        sf1a <= '0'; sf1b <= '0'; sf2a <= '0'; sf2b <= '0';
        safe_ok <= '0'; safe_ok_d <= '0';
        ana_phase  <= 0;
        telem_period <= to_unsigned(TELEM_MS, 16);
        ms_presc   <= 0;
        ms_cnt     <= (others => '0');
        if ADC_PRESENT then              -- (evita logica morta sui target senza ADC)
          thr   <= (others => '1');       -- soglie a fondo scala: nessun allarme
          cmp_d <= (others => '0');
        end if;
        pending_cmp <= '0';
      else
        -- sincronizzazione a 2FF dei canali di sicurezza
        sf1a <= to_x01(safe_ch1); sf1b <= sf1a;
        sf2a <= to_x01(safe_ch2); sf2b <= sf2a;
        safe_ok   <= sf1b and sf2b;
        safe_ok_d <= safe_ok;
        if safe_ok /= safe_ok_d then
          pending_status <= '1';
        end if;

        -- notifica immediata al variare della sovracorrente
        if ADC_PRESENT then
          cmp_d <= cmp;
          if cmp /= cmp_d then
            pending_cmp <= '1';
          end if;
        end if;

        ----------------------------------------------------------------------
        -- Timer periodico (base dei ms) per la telemetria ADC
        ----------------------------------------------------------------------
        if ms_presc = MS_TICKS-1 then
          ms_presc <= 0;
          if telem_period /= 0 and ADC_PRESENT then
            if ms_cnt >= telem_period - 1 then
              ms_cnt <= (others => '0');
              if ana_phase = 0 then
                ana_phase <= 1;         -- avvia la sequenza di trasmissione ADC
              end if;
            else
              ms_cnt <= ms_cnt + 1;
            end if;
          else
            ms_cnt <= (others => '0');
          end if;
        else
          ms_presc <= ms_presc + 1;
        end if;

        ----------------------------------------------------------------------
        -- Decodifica delle trame ricevute indirizzate a questo nodo
        ----------------------------------------------------------------------
        if rx_valid = '1' and rx_id(7 downto 4) = node_addr then
          case rx_id(10 downto 8) is
            when FUNC_MOTOR =>
              for k in 0 to 7 loop
                b := rx_data(63-8*k downto 56-8*k);
                mode_r(k) <= b(7 downto 6);
                duty_r(k) <= unsigned(b(5 downto 0));
              end loop;

            when FUNC_CONFIG =>
              if rx_id(3 downto 0) = "0000" then
                safe_mode <= rx_data(56);   -- byte0 bit0
                sel0_cfg  <= rx_data(57);   -- byte0 bit1
              elsif ADC_PRESENT and rx_id(3 downto 0) = "0001" then
                thr(15 downto 0)   <= rx_data(63 downto 48);  -- soglia motore 0
                thr(31 downto 16)  <= rx_data(47 downto 32);  -- soglia motore 1
                thr(47 downto 32)  <= rx_data(31 downto 16);  -- soglia motore 2
                thr(63 downto 48)  <= rx_data(15 downto 0);   -- soglia motore 3
              elsif ADC_PRESENT and rx_id(3 downto 0) = "0010" then
                thr(79 downto 64)   <= rx_data(63 downto 48); -- soglia motore 4
                thr(95 downto 80)   <= rx_data(47 downto 32); -- soglia motore 5
                thr(111 downto 96)  <= rx_data(31 downto 16); -- soglia motore 6
                thr(127 downto 112) <= rx_data(15 downto 0);  -- soglia motore 7
              end if;

            when FUNC_REQUEST =>
              pending_status <= '1';

            when FUNC_PERIOD =>
              telem_period <= unsigned(rx_data(63 downto 48));
              ms_cnt       <= (others => '0');

            when others =>
              null;
          end case;
        end if;

        ----------------------------------------------------------------------
        -- Scheduler di trasmissione
        ----------------------------------------------------------------------
        if tx_done = '1' then
          txreq <= '0';
          if cur_job = JOB_STATUS then
            pending_status <= '0';
          elsif cur_job = JOB_ACMP then
            pending_cmp <= '0';
          end if;
          cur_job <= JOB_NONE;
        elsif txreq = '0' and tx_busy = '0' and cur_job = JOB_NONE then
          if pending_status = '1' then
            cur_job  <= JOB_STATUS;
            txid_r   <= FUNC_STATUS & node_addr & "0000";
            txdata_r <= flags_byte & cmp & x"000000000000";
            txdlc_r  <= "0010";
            txreq    <= '1';
          elsif pending_cmp = '1' then
            cur_job  <= JOB_ACMP;
            txid_r   <= FUNC_ANALOG & node_addr & "0010";
            txdata_r <= cmp & x"00000000000000";
            txdlc_r  <= "0001";
            txreq    <= '1';
          elsif ana_phase = 1 then
            cur_job  <= JOB_ANA0;
            ana_phase <= 2;
            txid_r   <= FUNC_ANALOG & node_addr & "0000";
            txdata_r <= ana_blk0;
            txdlc_r  <= "1000";
            txreq    <= '1';
          elsif ana_phase = 2 then
            cur_job  <= JOB_ANA1;
            ana_phase <= 0;
            pending_cmp <= '1';         -- in coda: bitmap sovracorrente
            txid_r   <= FUNC_ANALOG & node_addr & "0001";
            txdata_r <= ana_blk1;
            txdlc_r  <= "1000";
            txreq    <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
