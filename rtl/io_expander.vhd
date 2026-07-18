--------------------------------------------------------------------------------
-- io_expander.vhd
--
-- Livello applicativo dell'espansore: 32 I/O bidirezionali, funzione di
-- sicurezza a doppio canale e lettura di 8 encoder incrementali, il tutto
-- comandato/riportato via CAN. Possiede l'unica interfaccia di trasmissione
-- del controller e ne schedula l'uso.
--
-- Identificatori (11 bit) = FUNC(3) & NODE_ADDR(4) & SUB(4):
--   FUNC="000" ENC_PERIOD (host->exp): data[63:48] = periodo TX encoder in ms
--                                      (0 = disabilita la trasmissione periodica)
--   FUNC="001" OUTPUT     (host->exp): data[63:32] = valori uscite
--                                      se DLC=8: data[31:0] = maschera scrittura
--   FUNC="010" CONFIG     (host->exp): data[63:32] = maschera direzione (1=uscita)
--   FUNC="011" REQUEST    (host->exp): richiede l'invio immediato dello STATUS
--   FUNC="100" STATUS     (exp->host): data[63:32] = stato pin
--   FUNC="101" ENC_RESET  (host->exp): data[7:0] = bitmask (bit i azzera encoder i)
--   FUNC="110" ENC_DATA   (exp->host): conteggi encoder. SUB=0 -> enc0..3,
--                                      SUB=1 -> enc4..7. 4 x int16, MSB=enc piu' basso.
--
-- I contatori encoder (16 bit con segno) arrivano da 8 quad_decoder esterni via
-- enc_count; enc_rst azzera i contatori selezionati.
--
-- Mappatura pin nel payload (CONFIG/OUTPUT/STATUS): pin i = bit (32+i).
--
-- FUNZIONE DI SICUREZZA (doppio canale fail-safe): safe_ch1/safe_ch2 consensi
-- attivi-alti. Uscite abilitate solo se ENTRAMBI alti; altrimenti tutte le
-- uscite sono forzate a low (auto-ripristino). Ogni transizione genera uno STATUS.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity io_expander is
  generic (
    MS_TICKS       : positive := 20000;  -- cicli di clk per 1 ms (20 MHz -> 20000)
    ENC_PERIOD_MS  : natural  := 10      -- periodo TX encoder di default (0 = off)
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

    -- encoder: 8 contatori a 16 bit (enc i = bit 16*i+15 .. 16*i) e reset
    enc_count  : in    std_logic_vector(127 downto 0);
    enc_rst    : out   std_logic_vector(7 downto 0);

    -- pin bidirezionali verso il mondo esterno
    io         : inout std_logic_vector(31 downto 0)
  );
end entity io_expander;

architecture rtl of io_expander is

  constant FUNC_ENCPER  : std_logic_vector(2 downto 0) := "000";
  constant FUNC_OUTPUT  : std_logic_vector(2 downto 0) := "001";
  constant FUNC_CONFIG  : std_logic_vector(2 downto 0) := "010";
  constant FUNC_REQUEST : std_logic_vector(2 downto 0) := "011";
  constant FUNC_STATUS  : std_logic_vector(2 downto 0) := "100";
  constant FUNC_ENCRST  : std_logic_vector(2 downto 0) := "101";
  constant FUNC_ENC     : std_logic_vector(2 downto 0) := "110";

  type job_t is (JOB_NONE, JOB_STATUS, JOB_ENC0, JOB_ENC1);

  signal dir      : std_logic_vector(31 downto 0) := (others => '0');
  signal outv     : std_logic_vector(31 downto 0) := (others => '0');
  signal io_in    : std_logic_vector(31 downto 0) := (others => '0');  -- ingressi sincronizzati (1FF)
  signal last_rep : std_logic_vector(31 downto 0) := (others => '0');

  signal status_word   : std_logic_vector(31 downto 0);
  signal input_changed : std_logic;
  signal outv_eff      : std_logic_vector(31 downto 0);

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
  signal txdlc_r        : std_logic_vector(3 downto 0)  := "0100";

  -- encoder / timer periodico
  signal enc_rst_r    : std_logic_vector(7 downto 0) := (others => '0');
  signal enc_phase    : integer range 0 to 2 := 0;    -- 0=idle,1=inviare blk0,2=inviare blk1
  signal enc_period   : unsigned(15 downto 0) := to_unsigned(ENC_PERIOD_MS, 16);
  signal ms_presc     : integer range 0 to MS_TICKS-1 := 0;
  signal ms_cnt       : unsigned(15 downto 0) := (others => '0');
  signal enc_blk0     : std_logic_vector(63 downto 0);
  signal enc_blk1     : std_logic_vector(63 downto 0);

begin

  ----------------------------------------------------------------------------
  -- Uscite effettive: forzate a low se manca il consenso di sicurezza.
  ----------------------------------------------------------------------------
  outv_eff <= outv when safe_ok = '1' else (others => '0');

  gen_io : for i in 0 to 31 generate
    io(i) <= outv_eff(i) when dir(i) = '1' else 'Z';
  end generate;

  status_word   <= (outv_eff and dir) or (io_in and not dir);
  input_changed <= '1' when (io_in and not dir) /= (last_rep and not dir) else '0';

  -- payload encoder: 4 x int16, encoder piu' basso nei byte piu' significativi
  enc_blk0 <= enc_count(15 downto 0)  & enc_count(31 downto 16) &
              enc_count(47 downto 32) & enc_count(63 downto 48);
  enc_blk1 <= enc_count(79 downto 64)   & enc_count(95 downto 80) &
              enc_count(111 downto 96)  & enc_count(127 downto 112);

  -- uscite verso il controller / decoder
  tx_request <= txreq;
  tx_id      <= txid_r;
  tx_rtr     <= '0';
  tx_dlc     <= txdlc_r;
  tx_data    <= txdata_r;
  enc_rst    <= enc_rst_r;

  process (clk)
    variable mask : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        dir      <= (others => '0');
        outv     <= (others => '0');
        io_in    <= (others => '0');
        last_rep <= (others => '0');
        pending_status <= '0';
        cur_job  <= JOB_NONE;
        txreq    <= '0';
        sf1a <= '0'; sf1b <= '0'; sf2a <= '0'; sf2b <= '0';
        safe_ok <= '0'; safe_ok_d <= '0';
        enc_rst_r  <= (others => '0');
        enc_phase  <= 0;
        enc_period <= to_unsigned(ENC_PERIOD_MS, 16);
        ms_presc   <= 0;
        ms_cnt     <= (others => '0');
      else
        -- impulso di reset encoder di default a 0 (attivo 1 clk su comando)
        enc_rst_r <= (others => '0');

        -- sincronizzazione a 1FF degli ingressi I/O (segnali lenti)
        io_in <= to_x01(io);

        -- sincronizzazione a 2FF dei canali di sicurezza
        sf1a <= to_x01(safe_ch1); sf1b <= sf1a;
        sf2a <= to_x01(safe_ch2); sf2b <= sf2a;
        safe_ok   <= sf1b and sf2b;
        safe_ok_d <= safe_ok;
        if safe_ok /= safe_ok_d then
          pending_status <= '1';
        end if;

        ----------------------------------------------------------------------
        -- Timer periodico (base dei ms) per la trasmissione degli encoder
        ----------------------------------------------------------------------
        if ms_presc = MS_TICKS-1 then
          ms_presc <= 0;
          if enc_period /= 0 then
            if ms_cnt >= enc_period - 1 then
              ms_cnt <= (others => '0');
              if enc_phase = 0 then
                enc_phase <= 1;              -- avvia invio blk0 poi blk1
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
            when FUNC_CONFIG =>
              dir <= rx_data(63 downto 32);

            when FUNC_OUTPUT =>
              if rx_dlc = "1000" then
                mask := rx_data(31 downto 0);
              else
                mask := (others => '1');
              end if;
              outv <= (outv and not mask) or (rx_data(63 downto 32) and mask);

            when FUNC_REQUEST =>
              pending_status <= '1';

            when FUNC_ENCRST =>
              enc_rst_r <= rx_data(7 downto 0);   -- bit i azzera encoder i

            when FUNC_ENCPER =>
              enc_period <= unsigned(rx_data(63 downto 48));
              ms_cnt     <= (others => '0');

            when others =>
              null;
          end case;
        end if;

        -- variazione di un ingresso -> invio automatico dello STATUS
        if input_changed = '1' then
          pending_status <= '1';
        end if;

        ----------------------------------------------------------------------
        -- Scheduler di trasmissione (STATUS prioritario, poi encoder blk0/blk1)
        ----------------------------------------------------------------------
        if tx_done = '1' then
          txreq <= '0';
          if cur_job = JOB_STATUS then
            pending_status <= '0';
            last_rep       <= status_word;
          end if;
          cur_job <= JOB_NONE;
        elsif txreq = '0' and tx_busy = '0' and cur_job = JOB_NONE then
          if pending_status = '1' then
            cur_job  <= JOB_STATUS;
            txid_r   <= FUNC_STATUS & node_addr & "0000";
            txdata_r <= status_word & x"00000000";
            txdlc_r  <= "0100";
            txreq    <= '1';
          elsif enc_phase = 1 then
            cur_job  <= JOB_ENC0;
            enc_phase <= 2;
            txid_r   <= FUNC_ENC & node_addr & "0000";
            txdata_r <= enc_blk0;
            txdlc_r  <= "1000";
            txreq    <= '1';
          elsif enc_phase = 2 then
            cur_job  <= JOB_ENC1;
            enc_phase <= 0;
            txid_r   <= FUNC_ENC & node_addr & "0001";
            txdata_r <= enc_blk1;
            txdlc_r  <= "1000";
            txreq    <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
