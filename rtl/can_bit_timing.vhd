--------------------------------------------------------------------------------
-- can_bit_timing.vhd
--
-- Generatore di temporizzazione di bit CAN.
-- Divide il tempo di bit in "time quanta" (Tq) e genera:
--   * tx_point     : impulso di 1 clk all'inizio di ogni bit (istante in cui il
--                    MAC deve aggiornare il livello pilotato sul bus)
--   * sample_point : impulso di 1 clk all'istante di campionamento (fra TSEG1 e
--                    TSEG2)
--
-- Sincronizzazione:
--   * hard sync   : quando il bus e' idle (bus_idle='1'), ogni fronte
--                   recessivo->dominante riallinea l'inizio del bit (SOF).
--   * resync soft : durante la trama, correzione dell'errore di fase positivo
--                   limitata a SJW (sufficiente con oscillatori allineati).
--
-- Parametri di default: 20 MHz, 500 kbit/s.
--   Tq  = BRP / f_clk = 2 / 20MHz = 100 ns
--   NTQ = 1 + TSEG1 + TSEG2 = 1 + 15 + 4 = 20 Tq  ->  2 us  ->  500 kbit/s
--   Sample point a (1+15)/20 = 80%
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_bit_timing is
  generic (
    BRP   : positive := 2;    -- prescaler: cicli di clk per Tq
    TSEG1 : positive := 15;   -- Tq del segmento prima del sample point
    TSEG2 : positive := 4;    -- Tq del segmento dopo il sample point
    SJW   : positive := 3     -- Tq di ampiezza massima di risincronizzazione
  );
  port (
    clk          : in  std_logic;
    rst_n        : in  std_logic;
    rx_sync      : in  std_logic;   -- livello del bus sincronizzato (0 = dominante)
    bus_idle     : in  std_logic;   -- '1' quando il MAC e' in idle (abilita hard sync)
    sample_point : out std_logic;   -- impulso di 1 clk all'istante di campionamento
    tx_point     : out std_logic    -- impulso di 1 clk all'inizio del bit
  );
end entity can_bit_timing;

architecture rtl of can_bit_timing is
  constant NTQ : integer := 1 + TSEG1 + TSEG2;
  signal presc   : integer range 0 to BRP-1 := 0;
  signal tqcnt   : integer range 0 to NTQ-1 := 0;
  signal prev_rx : std_logic := '1';
begin

  process (clk)
    variable do_tick : boolean;
    variable edge    : boolean;
  begin
    if rising_edge(clk) then
      sample_point <= '0';
      tx_point     <= '0';

      if rst_n = '0' then
        presc   <= 0;
        tqcnt   <= 0;
        prev_rx <= '1';
      else
        -- rilevazione fronte recessivo -> dominante
        edge    := (prev_rx = '1' and rx_sync = '0');
        prev_rx <= rx_sync;

        if edge and bus_idle = '1' then
          --------------------------------------------------------------
          -- Hard sync: il bit riparte allineato al fronte di SOF.
          --------------------------------------------------------------
          presc <= 0;
          tqcnt <= 0;
        elsif edge and bus_idle = '0' and tqcnt /= 0 then
          --------------------------------------------------------------
          -- Resync soft (solo errore di fase positivo), limitato a SJW.
          --------------------------------------------------------------
          if tqcnt <= SJW then
            tqcnt <= 0;
          else
            tqcnt <= tqcnt - SJW;
          end if;
          presc <= 0;
        else
          --------------------------------------------------------------
          -- Avanzamento normale della temporizzazione.
          --------------------------------------------------------------
          if presc = BRP-1 then
            presc   <= 0;
            do_tick := true;
          else
            presc   <= presc + 1;
            do_tick := false;
          end if;

          if do_tick then
            if tqcnt = NTQ-1 then
              tqcnt    <= 0;
              tx_point <= '1';          -- inizio di un nuovo bit
            else
              if tqcnt = TSEG1 then
                sample_point <= '1';    -- fine TSEG1 -> campiona
              end if;
              tqcnt <= tqcnt + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
