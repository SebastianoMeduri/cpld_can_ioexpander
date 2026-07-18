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
--   * generazione/riconoscimento dell'ACK.
--   * ritrasmissione automatica: finche' tx_request resta alto e la trama non
--     e' stata confermata (ACK), il MAC ritenta al successivo bus idle.
--
-- Convenzione livelli: '0' = dominante, '1' = recessivo.
--
-- NOTA: la gestione degli errori (error frame, contatori TEC/REC, bus-off)
--       e' semplificata: in caso di stuff/bit/form error il MAC emette un
--       error flag dominante e ritorna in idle. Vedere doc/protocol.md.
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
    tx_request   : in  std_logic;   -- livello: trama da inviare (tenere alto fino a tx_done)
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

    -- stato
    error_flag   : out std_logic    -- impulso su errore rilevato
  );
end entity can_mac;

architecture rtl of can_mac is

  type state_t is (ST_IDLE, ST_ID, ST_RTR, ST_IDE, ST_R0, ST_DLC,
                   ST_DATA, ST_CRC, ST_CRC_DELIM, ST_ACK, ST_ACK_DELIM,
                   ST_EOF, ST_IFS, ST_ERROR);

  signal state           : state_t := ST_IDLE;
  signal bitpos          : integer range 0 to 63 := 0;
  signal is_tx           : std_logic := '0';   -- '1' se questo nodo sta trasmettendo
  signal drive_r         : std_logic := '1';   -- livello pilotato (registrato)
  signal stuff_slot      : std_logic := '0';   -- lo slot corrente e' un bit di stuffing
  signal stuffing_active : std_logic := '0';   -- regione soggetta a bit stuffing
  signal stuff_cnt       : integer range 0 to 7 := 0;
  signal last_stream     : std_logic := '1';   -- ultimo bit dello stream (per stuffing)
  signal crc_calc        : std_logic_vector(14 downto 0) := (others => '0');

  -- registri di ricezione
  signal rxl_id   : std_logic_vector(10 downto 0) := (others => '0');
  signal rxl_rtr  : std_logic := '0';
  signal rxl_ide  : std_logic := '0';
  signal rxl_dlc  : std_logic_vector(3 downto 0) := (others => '0');
  signal rxl_data : std_logic_vector(63 downto 0) := (others => '0');
  signal rxl_crc  : std_logic_vector(14 downto 0) := (others => '0');
  signal databits : integer range 0 to 64 := 0;
  signal rx_crc_ok: std_logic := '0';

  -- registri di trasmissione (latch all'inizio trama)
  signal txl_id   : std_logic_vector(10 downto 0) := (others => '0');
  signal txl_rtr  : std_logic := '0';
  signal txl_dlc  : std_logic_vector(3 downto 0) := (others => '0');
  signal txl_data : std_logic_vector(63 downto 0) := (others => '0');
  signal tx_ack_ok: std_logic := '0';

begin

  can_tx   <= drive_r;
  bus_idle <= '1' when state = ST_IDLE else '0';
  tx_busy  <= is_tx;
  rx_id    <= rxl_id;
  rx_rtr   <= rxl_rtr;
  rx_dlc   <= rxl_dlc;
  rx_data  <= rxl_data;

  process (clk)
    variable sampled  : std_logic;
    variable curbit   : std_logic;
    variable dlc_i    : integer range 0 to 15;
    variable dbits    : integer range 0 to 64;
    variable goto_err : boolean;
    variable txbit    : std_logic;
  begin
    if rising_edge(clk) then
      -- impulsi di default
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
      else

        ------------------------------------------------------------------
        -- TX POINT: scelta del livello da pilotare per il bit che inizia
        ------------------------------------------------------------------
        if tx_point = '1' then
          if state = ST_IDLE then
            stuff_slot <= '0';
            if tx_request = '1' and rx_sync = '1' then
              -- inizio trama: pilota il SOF (dominante) e diventa trasmettitore
              drive_r <= '0';
              is_tx   <= '1';
              txl_id  <= tx_id;
              txl_rtr <= tx_rtr;
              txl_dlc <= tx_dlc;
              txl_data<= tx_data;
            else
              drive_r <= '1';
              is_tx   <= '0';
            end if;

          elsif state = ST_ERROR then
            stuff_slot <= '0';
            if bitpos < 6 then
              drive_r <= '0';   -- error flag dominante
            else
              drive_r <= '1';   -- delimitatore recessivo
            end if;

          else
            if stuffing_active = '1' and stuff_cnt = 5 then
              -- questo slot e' un bit di stuffing
              stuff_slot <= '1';
              if is_tx = '1' then
                drive_r <= not last_stream;   -- il trasmettitore inserisce lo stuff
              else
                drive_r <= '1';               -- il ricevitore ascolta
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
                  when others  => txbit := '1';   -- delimitatori/ACK/EOF/IFS
                end case;
                drive_r <= txbit;
              else
                -- ricevitore: recessivo, tranne lo slot di ACK se la trama e' valida
                if state = ST_ACK and rx_crc_ok = '1' then
                  drive_r <= '0';
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
          sampled  := rx_sync;
          curbit   := sampled;
          goto_err := false;

          -- monitoraggio del bus quando si trasmette
          if is_tx = '1' and state /= ST_IDLE and state /= ST_ERROR then
            if (state = ST_ID or state = ST_RTR) and drive_r = '1' and sampled = '0' then
              is_tx <= '0';               -- arbitraggio perso -> diventa ricevitore
            elsif state = ST_ACK then
              null;                       -- il trasmettitore si aspetta l'ACK dominante
            elsif drive_r /= sampled then
              goto_err := true;           -- bit error
            end if;
          end if;

          if goto_err then
            state           <= ST_ERROR;
            bitpos          <= 0;
            stuffing_active <= '0';
            stuff_cnt       <= 0;
            rx_crc_ok       <= '0';
            error_flag      <= '1';

          elsif stuff_slot = '1' then
            ----------------------------------------------------------------
            -- Slot di bit di stuffing: verifica e azzera il conteggio,
            -- senza far avanzare i campi ne' il CRC.
            ----------------------------------------------------------------
            if is_tx = '0' and sampled = last_stream then
              state           <= ST_ERROR;   -- stuff error
              bitpos          <= 0;
              stuffing_active <= '0';
              stuff_cnt       <= 0;
              rx_crc_ok       <= '0';
              error_flag      <= '1';
            else
              last_stream <= sampled;
              stuff_cnt   <= 1;
            end if;

          else
            ----------------------------------------------------------------
            -- Bit di campo "reale"
            ----------------------------------------------------------------
            -- aggiornamento CRC su SOF..DATA (non su CRC ne' delimitatore)
            if stuffing_active = '1' and state /= ST_CRC and state /= ST_CRC_DELIM then
              crc_calc <= crc15_next(crc_calc, curbit);
            end if;
            -- conteggio dei bit uguali consecutivi (per lo stuffing)
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
                if sampled = '0' then                 -- SOF rilevato
                  crc_calc        <= crc15_next("000000000000000", '0');
                  last_stream     <= '0';
                  stuff_cnt       <= 1;
                  stuffing_active <= '1';
                  rx_crc_ok       <= '0';
                  tx_ack_ok       <= '0';
                  rxl_rtr         <= '0';
                  rxl_ide         <= '0';
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
                rxl_ide <= curbit;
                state <= ST_R0; bitpos <= 0;

              when ST_R0 =>
                state <= ST_DLC; bitpos <= 0;

              when ST_DLC =>
                rxl_dlc(3 - bitpos) <= curbit;
                if bitpos = 3 then
                  dlc_i := to_integer(unsigned(rxl_dlc(3 downto 1) & curbit));
                  if rxl_rtr = '1' or dlc_i = 0 then
                    state <= ST_CRC; bitpos <= 0;      -- nessun campo dati
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
                stuffing_active <= '0';   -- fine della regione soggetta a stuffing
                state <= ST_ACK; bitpos <= 0;

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
                state <= ST_EOF; bitpos <= 0;

              when ST_EOF =>
                if bitpos = 6 then
                  state <= ST_IFS; bitpos <= 0;
                else
                  bitpos <= bitpos + 1;
                end if;

              when ST_IFS =>
                if bitpos = 2 then
                  if is_tx = '1' then
                    if tx_ack_ok = '1' then
                      tx_done <= '1';     -- trama confermata
                    end if;
                    is_tx <= '0';         -- (se non confermata, tx_request ancora alto -> ritenta)
                  elsif rx_crc_ok = '1' then
                    rx_valid <= '1';
                  end if;
                  state <= ST_IDLE; bitpos <= 0;
                else
                  bitpos <= bitpos + 1;
                end if;

              when ST_ERROR =>
                if bitpos >= 12 then
                  state <= ST_IDLE; bitpos <= 0;
                else
                  bitpos <= bitpos + 1;
                end if;

              when others =>
                state <= ST_IDLE; bitpos <= 0;
            end case;
          end if;  -- goto_err / stuff / reale
        end if;  -- sample_point
      end if;  -- rst
    end if;  -- clk
  end process;

end architecture rtl;
