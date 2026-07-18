--------------------------------------------------------------------------------
-- quad_decoder.vhd
--
-- Decodificatore di quadratura per encoder incrementale (canali A/B).
-- Decodifica x4: conta un impulso su OGNI transizione valida di A o B, con
-- direzione dedotta dalla sequenza di Gray. Contatore a 16 bit con segno.
--
--   avanti  (fwd): 00 -> 01 -> 11 -> 10 -> 00   (+1 per transizione)
--   indietro(rev): 00 -> 10 -> 11 -> 01 -> 00   (-1 per transizione)
--   transizioni doppie/illegali: ignorate (nessun conteggio)
--
-- Gli ingressi A/B sono sincronizzati internamente a 2 flip-flop
-- (protezione da metastabilita', tollera 'H'/'L' dal bus).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity quad_decoder is
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    a         : in  std_logic;                     -- canale A encoder
    b         : in  std_logic;                     -- canale B encoder
    rst_count : in  std_logic;                     -- azzera il contatore (sincrono)
    count     : out std_logic_vector(15 downto 0)  -- conteggio con segno
  );
end entity quad_decoder;

architecture rtl of quad_decoder is
  signal a1, a2 : std_logic := '0';
  signal b1, b2 : std_logic := '0';
  signal prev   : std_logic_vector(1 downto 0) := "00";
  signal cnt    : signed(15 downto 0) := (others => '0');
begin

  count <= std_logic_vector(cnt);

  process (clk)
    variable cur : std_logic_vector(1 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        a1 <= '0'; a2 <= '0'; b1 <= '0'; b2 <= '0';
        prev <= "00";
        cnt  <= (others => '0');
      else
        -- sincronizzazione a 2FF
        a1 <= to_x01(a); a2 <= a1;
        b1 <= to_x01(b); b2 <= b1;

        cur := a2 & b2;

        if rst_count = '1' then
          cnt <= (others => '0');
        else
          case prev & cur is
            when "0001" | "0111" | "1110" | "1000" =>
              cnt <= cnt + 1;                     -- avanti
            when "0010" | "1011" | "1101" | "0100" =>
              cnt <= cnt - 1;                     -- indietro
            when others =>
              null;                               -- nessuna transizione o illegale
          end case;
        end if;

        prev <= cur;
      end if;
    end if;
  end process;

end architecture rtl;
