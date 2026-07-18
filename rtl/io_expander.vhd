--------------------------------------------------------------------------------
-- io_expander.vhd
--
-- Espansore di I/O a 32 pin bidirezionali comandato via CAN.
-- Ogni pin e' configurabile individualmente come ingresso o uscita.
--
-- Mappatura dei pin nel payload CAN (4 byte = 32 bit):
--   il pin i corrisponde al bit (32 + i) della trama a 64 bit,
--   cioe' i primi 4 byte del campo dati (byte0 = pin31..24, ... byte3 = pin7..0).
--
-- Identificatori (11 bit) = FUNC(3) & NODE_ADDR(4) & "0000":
--   FUNC="010" CONFIG  (host->exp): data[63:32] = maschera direzione (1=uscita)
--   FUNC="001" OUTPUT  (host->exp): data[63:32] = valori uscite
--                                   se DLC=8: data[31:0] = maschera di scrittura
--   FUNC="011" REQUEST (host->exp): richiede l'invio immediato dello stato
--   FUNC="100" STATUS  (exp->host): data[63:32] = stato pin (uscite: valore
--                                   pilotato, ingressi: valore letto)
--
-- Lo STATUS viene inviato: su richiesta (REQUEST) e automaticamente al variare
-- di un qualunque pin configurato come ingresso.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity io_expander is
  port (
    clk        : in    std_logic;
    rst_n      : in    std_logic;
    node_addr  : in    std_logic_vector(3 downto 0);

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

    -- pin bidirezionali verso il mondo esterno
    io         : inout std_logic_vector(31 downto 0)
  );
end entity io_expander;

architecture rtl of io_expander is

  constant FUNC_CONFIG  : std_logic_vector(2 downto 0) := "010";
  constant FUNC_OUTPUT  : std_logic_vector(2 downto 0) := "001";
  constant FUNC_REQUEST : std_logic_vector(2 downto 0) := "011";
  constant FUNC_STATUS  : std_logic_vector(2 downto 0) := "100";

  signal dir      : std_logic_vector(31 downto 0) := (others => '0'); -- 1 = uscita
  signal outv     : std_logic_vector(31 downto 0) := (others => '0'); -- valori uscite
  signal io_s1    : std_logic_vector(31 downto 0) := (others => '0');
  signal io_in    : std_logic_vector(31 downto 0) := (others => '0'); -- ingressi sincronizzati
  signal last_rep : std_logic_vector(31 downto 0) := (others => '0'); -- ultimo stato notificato

  signal status_word   : std_logic_vector(31 downto 0);
  signal input_changed : std_logic;

  signal pending  : std_logic := '0';
  signal txreq    : std_logic := '0';
  signal txid_r   : std_logic_vector(10 downto 0) := (others => '0');
  signal txdata_r : std_logic_vector(63 downto 0) := (others => '0');
  signal txdlc_r  : std_logic_vector(3 downto 0)  := "0100";

begin

  ----------------------------------------------------------------------------
  -- Pilotaggio dei pin bidirezionali: uscita se dir='1', altrimenti alta impedenza.
  ----------------------------------------------------------------------------
  gen_io : for i in 0 to 31 generate
    io(i) <= outv(i) when dir(i) = '1' else 'Z';
  end generate;

  ----------------------------------------------------------------------------
  -- Stato riportato: per le uscite il valore pilotato, per gli ingressi il letto.
  ----------------------------------------------------------------------------
  status_word   <= (outv and dir) or (io_in and not dir);
  input_changed <= '1' when (io_in and not dir) /= (last_rep and not dir) else '0';

  -- uscite verso il controller
  tx_request <= txreq;
  tx_id      <= txid_r;
  tx_rtr     <= '0';
  tx_dlc     <= txdlc_r;
  tx_data    <= txdata_r;

  process (clk)
    variable mask : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        dir      <= (others => '0');
        outv     <= (others => '0');
        io_s1    <= (others => '0');
        io_in    <= (others => '0');
        last_rep <= (others => '0');
        pending  <= '0';
        txreq    <= '0';
      else
        -- sincronizzazione a 2FF degli ingressi (mappa 'H'/'L' su '1'/'0')
        io_s1 <= to_x01(io);
        io_in <= io_s1;

        ----------------------------------------------------------------------
        -- Decodifica delle trame ricevute indirizzate a questo nodo
        ----------------------------------------------------------------------
        if rx_valid = '1' and rx_id(7 downto 4) = node_addr then
          case rx_id(10 downto 8) is
            when FUNC_CONFIG =>
              dir <= rx_data(63 downto 32);

            when FUNC_OUTPUT =>
              if rx_dlc = "1000" then       -- DLC = 8 -> maschera di scrittura presente
                mask := rx_data(31 downto 0);
              else
                mask := (others => '1');
              end if;
              outv <= (outv and not mask) or (rx_data(63 downto 32) and mask);

            when FUNC_REQUEST =>
              pending <= '1';

            when others =>
              null;
          end case;
        end if;

        -- variazione di un ingresso -> invio automatico dello stato
        if input_changed = '1' then
          pending <= '1';
        end if;

        ----------------------------------------------------------------------
        -- Gestione della trasmissione dello STATUS
        ----------------------------------------------------------------------
        if tx_done = '1' then
          txreq    <= '0';
          pending  <= '0';
          last_rep <= status_word;         -- fotografia dello stato notificato
        elsif pending = '1' and txreq = '0' and tx_busy = '0' then
          txreq    <= '1';
          txid_r   <= FUNC_STATUS & node_addr & "0000";
          txdata_r <= status_word & x"00000000";
          txdlc_r  <= "0100";              -- 4 byte
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
