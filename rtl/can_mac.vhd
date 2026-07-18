--------------------------------------------------------------------------------
-- can_mac.vhd
--
-- Livello MAC del controller CAN 2.0A (identificatore standard a 11 bit).
-- Un'unica macchina a stati gestisce sia la trasmissione sia la ricezione,
-- pilotata dagli impulsi sample_point / tx_point del bit timing.
--
-- Funzioni implementate:
--   * SOF, arbitraggio (ID+RTR), controllo (IDE,r0,DLC), dati, CRC-15,
--     delimitatori, ACK, EOF, IFS.
--   * bit stuffing / de-stuffing (5 bit uguali -> 1 bit di stuffing).
--   * monitoraggio del bus in trasmissione: perdita di arbitraggio e bit error.
--   * rilevazione errori: bit error, stuff error, form error (delimitatori/EOF),
--     ACK error (trasmettitore), CRC error (ricevitore).
--   * error frame: flag attivo (6 dominanti) se error-active, flag passivo
--     (6 recessivi) se error-passive, seguito da error delimiter (8 recessivi).
--   * fault confinement ISO 11898-1 (semplificato): contatori TEC/REC, stati
--     error-active / error-passive / bus-off e recupero da bus-off dopo
--     128 sequenze di 11 bit recessivi.
--   * ritrasmissione automatica finche' tx_request resta alto.
--
-- Convenzione livelli: '0' = dominante, '1' = recessivo.
--
-- Semplificazioni note rispetto a ISO 11898-1: regole TEC/REC ridotte
-- (incrementi +8 tx / +1 rx, decremento -1 su successo), nessun overload
-- frame, nessuna sospensione di trasmissione (8 bit) per i nodi error-passive.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.can_pkg.all;

entity can_mac is
  port (
    clk          : in  std_logic;
    rst_n        : in  std_logic;

    -- dal bit timing
    sample_point : in  std_logic;
    tx_point     : in  std_logic;

    -- interfaccia bus (livelli sincronizzati)
    rx_sync      : in  std_logic;   -- livello campionato del bus (0 = dominante)
    can_tx       : out std_logic;   -- livello da pilotare (0 = dominante)
    bus_idle     : out std_logic;   -- '1' quando in idle

    -- interfaccia di trasmissione applicativa
    tx_request   : in  std_logic;
    tx_id        : in  std_logic_vector(10 downto 0);
    tx_rtr       : in  std_logic;
    tx_dlc       : in  std_logic_vector(3 downto 0);
    tx_data      : in  std_logic_vector(63 downto 0);  -- byte0 = bit 63..56
    tx_busy      : out std_logic;
    tx_done      : out std_logic;   -- impulso: trama trasmessa e confermata (ACK)

    -- interfaccia di ricezione applicativa
    rx_valid     : out std_logic;   -- impulso: trama ricevuta valida (CRC ok)
    rx_id        : out std_logic_vector(10 downto 0);
    rx_rtr       : out std_logic;
    rx_dlc       : out std_logic_vector(3 downto 0);
    rx_data      : out std_logic_vector(63 downto 0);

    -- stato / diagnostica
    error_flag    : out std_logic;                     -- impulso su errore rilevato
    error_passive : out std_logic;                     -- '1' se error-passive
    bus_off       : out std_logic;                     -- '1' se bus-off
    tec_value     : out std_logic_vector(7 downto 0)   -- Transmit Error Counter
  );
end entity can_mac;

architecture rtl of can_mac is

  type state_t is (ST_IDLE, ST_ID, ST_RTR, ST_IDE, ST_R0, ST_DLC,
                   ST_DATA, ST_CRC, ST_CRC_DELIM, ST_ACK, ST_ACK_DELIM,
                   ST_EOF, ST_IFS, ST_ERR_FLAG, ST_ERR_DELIM, ST_BUSOFF);

  type errstate_t is (ES_ACTIVE, ES_PASSIVE, ES_BUSOFF);

  signal state           : state_t := ST_IDLE;
  signal bitpos          : integer range 0 to 63 := 0;
  signal is_tx           : std_logic := '0';
  signal drive_r         : std_logic := '1';
  signal stuff_slot      : std_logic := '0';
  signal stuffing_active : std_logic := '0';
  signal stuff_cnt       : integer range 0 to 7 := 0;
  signal last_stream     : std_logic := '1';
  signal crc_calc        : std_logic_vector(14 downto 0) := (others => '0');

  -- registri di ricezione
  signal rxl_id   : std_logic_vector(10 downto 0) := (others => '0');
  signal rxl_rtr  : std_logic := '0';
  signal rxl_dlc  : std_logic_vector(3 downto 0) := (others => '0');
  signal rxl_data : std_logic_vector(63 downto 0) := (others => '0');
  signal rxl_crc  : std_logic_vector(14 downto 0) := (others => '0');
  signal databits : integer range 0 to 64 := 0;
  signal rx_crc_ok: std_logic := '0';

  -- registri di trasmissione
  signal txl_id   : std_logic_vector(10 downto 0) := (others => '0');
  signal txl_rtr  : std_logic := '0';
  signal txl_dlc  : std_logic_vector(3 downto 0) := (others => '0');
  signal txl_data : std_logic_vector(63 downto 0) := (others => '0');
  signal tx_ack_ok: std_logic := '0';

  -- fault confinement
  signal tec         : integer range 0 to 255 := 0;
  signal rec         : integer range 0 to 255 := 0;
  signal busoff_latch: std_logic := '0';
  signal err_state   : errstate_t;
  signal recov_cnt   : integer range 0 to 127 := 0;  -- sequenze da 11 bit recessivi
  signal rec_run     : integer range 0 to 15 := 0;   -- bit recessivi consecutivi

begin

  can_tx   <= drive_r;
  bus_idle <= '1' when state = ST_IDLE else '0';
  tx_busy  <= is_tx;
  rx_id    <= rxl_id;
  rx_rtr   <= rxl_rtr;
  rx_dlc   <= rxl_dlc;
  rx_data  <= rxl_data;

  -- stato di fault confinement (combinatorio dai contatori)
  err_state <= ES_BUSOFF  when busoff_latch = '1'
          else ES_PASSIVE when (tec > 127 or rec > 127)
          else ES_ACTIVE;

  error_passive <= '1' when err_state = ES_PASSIVE else '0';
  bus_off       <= '1' when err_state = ES_BUSOFF  else '0';
  tec_value     <= std_logic_vector(to_unsigned(tec, 8));

  process (clk)
    variable sampled  : std_logic;
    variable curbit   : std_logic;
    variable dlc_i    : integer range 0 to 15;
    variable dbits    : integer range 0 to 64;
    variable do_err   : boolean;
    variable txbit    : std_logic;

    -- Avvio di un error frame + aggiornamento contatori.
    -- tx_err = true  -> errore imputato al trasmettitore (TEC += 8)
    -- tx_err = false -> errore imputato al ricevitore    (REC += 1)
    procedure enter_error (tx_err : boolean) is
      variable ntec : integer;
    begin
      bitpos          <= 0;
      stuffing_active <= '0';
      stuff_cnt       <= 0;
      rx_crc_ok       <= '0';
      error_flag      <= '1';
      if tx_err then
        ntec := tec + 8;
        if ntec > 255 then
          tec          <= 255;
          busoff_latch <= '1';        -- bus-off
          recov_cnt    <= 0;
          rec_run      <= 0;
          state        <= ST_BUSOFF;
        else
          tec   <= ntec;
          state <= ST_ERR_FLAG;
        end if;
      else
        if rec < 255 then
          rec <= rec + 1;
        end if;
        state <= ST_ERR_FLAG;
      end if;
    end procedure;

  begin
    if rising_edge(clk) then
      rx_valid   <= '0';
      tx_done    <= '0';
      error_flag <= '0';

      if rst_n = '0' then
        state           <= ST_IDLE;
        bitpos          <= 0;
        is_tx           <= '0';
        drive_r         <= '1';
        stuff_slot      <= '0';
        stuffing_active <= '0';
        stuff_cnt       <= 0;
        last_stream     <= '1';
        crc_calc        <= (others => '0');
        rx_crc_ok       <= '0';
        tx_ack_ok       <= '0';
        tec             <= 0;
        rec             <= 0;
        busoff_latch    <= '0';
        recov_cnt       <= 0;
        rec_run         <= 0;
      else

        ------------------------------------------------------------------
        -- TX POINT: livello da pilotare per il bit che inizia
        ------------------------------------------------------------------
        if tx_point = '1' then
          if state = ST_IDLE then
            stuff_slot <= '0';
            if tx_request = '1' and rx_sync = '1' and busoff_latch = '0' then
              drive_r <= '0';         -- SOF
              is_tx   <= '1';
              txl_id  <= tx_id;
              txl_rtr <= tx_rtr;
              txl_dlc <= tx_dlc;
              txl_data<= tx_data;
            else
              drive_r <= '1';
              is_tx   <= '0';
            end if;

          elsif state = ST_ERR_FLAG then
            stuff_slot <= '0';
            if err_state = ES_ACTIVE then
              drive_r <= '0';         -- flag attivo: 6 dominanti
            else
              drive_r <= '1';         -- flag passivo: 6 recessivi
            end if;

          elsif state = ST_ERR_DELIM or state = ST_BUSOFF then
            stuff_slot <= '0';
            drive_r    <= '1';        -- recessivo (silenzioso)

          else
            if stuffing_active = '1' and stuff_cnt = 5 then
              stuff_slot <= '1';
              if is_tx = '1' then
                drive_r <= not last_stream;
              else
                drive_r <= '1';
              end if;
            else
              stuff_slot <= '0';
              if is_tx = '1' then
                case state is
                  when ST_ID   => txbit := txl_id(10 - bitpos);
                  when ST_RTR  => txbit := txl_rtr;
                  when ST_IDE  => txbit := '0';
                  when ST_R0   => txbit := '0';
                  when ST_DLC  => txbit := txl_dlc(3 - bitpos);
                  when ST_DATA => txbit := txl_data(63 - bitpos);
                  when ST_CRC  => txbit := crc_calc(14 - bitpos);
                  when others  => txbit := '1';
                end case;
                drive_r <= txbit;
              else
                if state = ST_ACK and rx_crc_ok = '1' then
                  drive_r <= '0';     -- ACK del ricevitore
                else
                  drive_r <= '1';
                end if;
              end if;
            end if;
          end if;
        end if;

        ------------------------------------------------------------------
        -- SAMPLE POINT: lettura del bus e avanzamento della macchina
        ------------------------------------------------------------------
        if sample_point = '1' then
          sampled := rx_sync;
          curbit  := sampled;
          do_err  := false;

          -- monitoraggio del bus in trasmissione (solo stati dati normali)
          if is_tx = '1' and state /= ST_IDLE and state /= ST_ERR_FLAG
             and state /= ST_ERR_DELIM and state /= ST_BUSOFF then
            if (state = ST_ID or state = ST_RTR) and drive_r = '1' and sampled = '0' then
              is_tx <= '0';                 -- arbitraggio perso
            elsif state = ST_ACK then
              null;
            elsif drive_r /= sampled then
              do_err := true;               -- bit error
            end if;
          end if;

          if do_err then
            enter_error(true);              -- bit error del trasmettitore

          elsif stuff_slot = '1' then
            ------------------------------------------------------------
            -- Slot di bit di stuffing
            ------------------------------------------------------------
            if is_tx = '0' and sampled = last_stream then
              enter_error(false);           -- stuff error (ricevitore)
            else
              last_stream <= sampled;
              stuff_cnt   <= 1;
            end if;

          else
            ------------------------------------------------------------
            -- Bit di campo "reale"
            ------------------------------------------------------------
            if stuffing_active = '1' and state /= ST_CRC and state /= ST_CRC_DELIM then
              crc_calc <= crc15_next(crc_calc, curbit);
            end if;
            if stuffing_active = '1' then
              if curbit = last_stream then
                stuff_cnt <= stuff_cnt + 1;
              else
                stuff_cnt <= 1;
              end if;
              last_stream <= curbit;
            end if;

            case state is
              when ST_IDLE =>
                if sampled = '0' then                 -- SOF
                  crc_calc        <= crc15_next("000000000000000", '0');
                  last_stream     <= '0';
                  stuff_cnt       <= 1;
                  stuffing_active <= '1';
                  rx_crc_ok       <= '0';
                  tx_ack_ok       <= '0';
                  rxl_rtr         <= '0';
                  state           <= ST_ID;
                  bitpos          <= 0;
                end if;

              when ST_ID =>
                rxl_id(10 - bitpos) <= curbit;
                if bitpos = 10 then
                  state <= ST_RTR; bitpos <= 0;
                else
                  bitpos <= bitpos + 1;
                end if;

              when ST_RTR =>
                rxl_rtr <= curbit;
                state <= ST_IDE; bitpos <= 0;

              when ST_IDE =>
                state <= ST_R0; bitpos <= 0;

              when ST_R0 =>
                state <= ST_DLC; bitpos <= 0;

              when ST_DLC =>
                rxl_dlc(3 - bitpos) <= curbit;
                if bitpos = 3 then
                  dlc_i := to_integer(unsigned(rxl_dlc(3 downto 1) & curbit));
                  if rxl_rtr = '1' or dlc_i = 0 then
                    state <= ST_CRC; bitpos <= 0;
                  else
                    dbits    := min2(dlc_i, 8) * 8;
                    databits <= dbits;
                    state    <= ST_DATA; bitpos <= 0;
                  end if;
                else
                  bitpos <= bitpos + 1;
                end if;

              when ST_DATA =>
                rxl_data(63 - bitpos) <= curbit;
                if bitpos = databits - 1 then
                  state <= ST_CRC; bitpos <= 0;
                else
                  bitpos <= bitpos + 1;
                end if;

              when ST_CRC =>
                rxl_crc(14 - bitpos) <= curbit;
                if bitpos = 14 then
                  if crc_calc = (rxl_crc(14 downto 1) & curbit) then
                    rx_crc_ok <= '1';
                  else
                    rx_crc_ok <= '0';
                  end if;
                  state <= ST_CRC_DELIM; bitpos <= 0;
                else
                  bitpos <= bitpos + 1;
                end if;

              when ST_CRC_DELIM =>
                stuffing_active <= '0';
                if sampled = '0' then
                  enter_error(is_tx = '1');           -- form error
                else
                  state <= ST_ACK; bitpos <= 0;
                end if;

              when ST_ACK =>
                if is_tx = '1' then
                  if sampled = '0' then
                    tx_ack_ok <= '1';
                  else
                    tx_ack_ok <= '0';
                  end if;
                end if;
                state <= ST_ACK_DELIM; bitpos <= 0;

              when ST_ACK_DELIM =>
                if sampled = '0' then
                  enter_error(is_tx = '1');           -- form error
                elsif is_tx = '1' and tx_ack_ok = '0' then
                  enter_error(true);                  -- ACK error (trasmettitore)
                elsif is_tx = '0' and rx_crc_ok = '0' then
                  enter_error(false);                 -- CRC error (ricevitore)
                else
                  state <= ST_EOF; bitpos <= 0;
                end if;

              when ST_EOF =>
                if sampled = '0' and bitpos <= 5 then
                  enter_error(is_tx = '1');           -- form error in EOF
                elsif bitpos = 6 then
                  state <= ST_IFS; bitpos <= 0;
                else
                  bitpos <= bitpos + 1;
                end if;

              when ST_IFS =>
                if bitpos = 2 then
                  if is_tx = '1' then
                    if tx_ack_ok = '1' then
                      tx_done <= '1';
                      if tec > 0 then tec <= tec - 1; end if;   -- successo tx
                    end if;
                    is_tx <= '0';
                  elsif rx_crc_ok = '1' then
                    rx_valid <= '1';
                    if rec > 0 then rec <= rec - 1; end if;     -- successo rx
                  end if;
                  state <= ST_IDLE; bitpos <= 0;
                else
                  bitpos <= bitpos + 1;
                end if;

              when ST_ERR_FLAG =>
                if err_state = ES_ACTIVE then
                  if bitpos >= 5 then                 -- 6 bit dominanti inviati
                    state <= ST_ERR_DELIM; bitpos <= 0;
                  else
                    bitpos <= bitpos + 1;
                  end if;
                else
                  -- flag passivo: attende 6 bit recessivi consecutivi
                  if sampled = '1' then
                    if bitpos >= 5 then
                      state <= ST_ERR_DELIM; bitpos <= 0;
                    else
                      bitpos <= bitpos + 1;
                    end if;
                  else
                    bitpos <= 0;
                  end if;
                end if;

              when ST_ERR_DELIM =>
                -- error delimiter: 8 bit recessivi consecutivi, poi idle
                if sampled = '1' then
                  if bitpos >= 7 then
                    is_tx <= '0';
                    state <= ST_IDLE; bitpos <= 0;
                  else
                    bitpos <= bitpos + 1;
                  end if;
                else
                  bitpos <= 0;
                end if;

              when ST_BUSOFF =>
                -- recupero: 128 sequenze di 11 bit recessivi consecutivi
                if sampled = '1' then
                  if rec_run >= 10 then
                    rec_run <= 0;
                    if recov_cnt >= 127 then
                      busoff_latch <= '0';
                      tec <= 0; rec <= 0;
                      is_tx <= '0';
                      state <= ST_IDLE; bitpos <= 0;
                    else
                      recov_cnt <= recov_cnt + 1;
                    end if;
                  else
                    rec_run <= rec_run + 1;
                  end if;
                else
                  rec_run <= 0;
                end if;

              when others =>
                state <= ST_IDLE; bitpos <= 0;
            end case;
          end if;  -- do_err / stuff / reale
        end if;  -- sample_point
      end if;  -- rst
    end if;  -- clk
  end process;

end architecture rtl;
