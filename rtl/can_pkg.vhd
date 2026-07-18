--------------------------------------------------------------------------------
-- can_pkg.vhd
--
-- Definizioni comuni per il core CAN 2.0A e per l'I/O expander:
--   * funzione CRC-15 (polinomio CAN 0x4599)
--   * funzione di utilita' min2()
--
-- Progetto: cpld_can_ioexpander
-- VHDL portabile (subset compatibile VHDL-93), vendor-neutral.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package can_pkg is

  -- Calcolo incrementale del CRC-15 usato dal protocollo CAN.
  -- Polinomio: x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1  (0x4599)
  -- Il CRC va inizializzato a zero e aggiornato un bit alla volta
  -- (bit "destuffati", dal SOF fino alla fine del campo dati incluso).
  function crc15_next (crc : std_logic_vector(14 downto 0);
                       din : std_logic) return std_logic_vector;

  -- Minimo fra due interi.
  function min2 (a, b : integer) return integer;

end package can_pkg;


package body can_pkg is

  function crc15_next (crc : std_logic_vector(14 downto 0);
                       din : std_logic) return std_logic_vector is
    variable fb : std_logic;
    variable c  : std_logic_vector(14 downto 0);
  begin
    fb := crc(14) xor din;
    c  := crc(13 downto 0) & '0';
    if fb = '1' then
      c := c xor "100010110011001";  -- 0x4599
    end if;
    return c;
  end function crc15_next;

  function min2 (a, b : integer) return integer is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function min2;

end package body can_pkg;
