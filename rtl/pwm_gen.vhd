--------------------------------------------------------------------------------
-- pwm_gen.vhd
--
-- Generatore PWM a canale singolo con prescaler di clock e caso speciale di
-- "fondoscala" per ottenere l'uscita statica (controllo on/off).
--
--   * la frequenza PWM = f_clk / (PRESCALE * 2**DUTY_BITS);
--   * duty in ingresso su DUTY_BITS bit (0 .. 2**DUTY_BITS-1);
--       - duty = 0            -> uscita sempre bassa (motore fermo / off);
--       - duty = fondoscala   -> uscita sempre alta (ON statico, controllo on/off);
--       - valori intermedi     -> PWM al duty richiesto.
--
-- Esempio MAX 10 (50 MHz), DUTY_BITS=6, PRESCALE=40:
--   f_pwm = 50e6 / (40 * 64) = 19,53 kHz  (entro il limite del VNH7100AS, ~20 kHz).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_gen is
  generic (
    DUTY_BITS : positive := 6;    -- risoluzione del duty (numero di passi = 2**DUTY_BITS)
    PRESCALE  : positive := 40    -- divisore di clock per la base dei tempi PWM
  );
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    duty  : in  unsigned(DUTY_BITS-1 downto 0);
    pwm   : out std_logic
  );
end entity pwm_gen;

architecture rtl of pwm_gen is
  constant FULL : unsigned(DUTY_BITS-1 downto 0) := (others => '1');  -- fondoscala
  signal cnt    : unsigned(DUTY_BITS-1 downto 0) := (others => '0');
  signal presc  : integer range 0 to PRESCALE-1 := 0;
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        cnt   <= (others => '0');
        presc <= 0;
      else
        if presc = PRESCALE-1 then
          presc <= 0;
          cnt   <= cnt + 1;             -- avvolge naturalmente a 2**DUTY_BITS
        else
          presc <= presc + 1;
        end if;
      end if;
    end if;
  end process;

  -- fondoscala -> sempre alto; altrimenti alto finche' cnt < duty (duty=0 -> sempre basso)
  pwm <= '1' when (duty = FULL) or (cnt < duty) else '0';

end architecture rtl;
