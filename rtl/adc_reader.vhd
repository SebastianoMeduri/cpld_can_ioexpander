--------------------------------------------------------------------------------
-- adc_reader.vhd  --  Front-end di lettura dell'ADC del MAX 10 (SOLO target MAX 10)
--
-- Legge in sequenza (round-robin) 8 canali dell'ADC hard del MAX 10 e li presenta
-- come vettore adc_val (8 x 16 bit, valore su 12 bit, canale i = bit 16*i+15..16*i).
--
-- ===========================  IMPORTANTE  ===================================
-- Questo modulo NON e' vendor-neutral e NON e' simulabile in GHDL: istanzia
-- l'IP hard "Altera Modular ADC Core" del MAX 10, che va GENERATO in Quartus.
-- Non fa parte del build MAX V ne' della simulazione.
--
-- PASSI PER ABILITARE L'ADC (in Quartus, target MAX 10):
--   1. IP Catalog -> "Altera Modular ADC Core":
--        - Core variant: "Standard sequencer" con interfaccia a comandi/risposte
--          (command/response Avalon-ST), oppure adatta i port qui sotto.
--        - Abilita i canali analogici desiderati (fino a 8) -> CH1..CH8.
--        - Clock ADC (adc_pll_clock): 10 MHz (tipico), da una PLL (vedi punto 2).
--        - Genera; annota il NOME dell'entita' generata e adegua il "component"
--          e la port map qui sotto (i nomi delle porte dipendono dalla config).
--   2. IP Catalog -> "Altera PLL": ingresso 50 MHz -> uscita per adc_pll_clock
--      (es. 10 MHz); collega 'locked' ad adc_pll_locked.
--   3. Aggiungi i file IP generati e questo file al progetto quartus_max10.
--   4. In can_ioexpander_max10 imposta ADC_PRESENT => true e istanzia adc_reader,
--      collegando adc_val al top (vedi doc/MANUALE.md).
--
-- I pin analogici sono pin dedicati/dual-purpose gestiti dall'IP (la loro
-- assegnazione avviene nella configurazione dell'IP, non come porte RTL).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adc_reader is
  generic (
    N_CH : integer range 1 to 8 := 8      -- numero di canali analogici letti
  );
  port (
    clk           : in  std_logic;        -- clock di sistema (50 MHz)
    rst_n         : in  std_logic;
    adc_pll_clk   : in  std_logic;        -- clock ADC dalla PLL (es. 10 MHz)
    adc_pll_lock  : in  std_logic;        -- 'locked' della PLL
    adc_val       : out std_logic_vector(127 downto 0)  -- 8 x 16 bit (12 bit utili)
  );
end entity adc_reader;

architecture rtl of adc_reader is

  -- Component dell'IP Modular ADC (ADEGUA i nomi a quelli generati in Quartus).
  component modular_adc is
    port (
      clock_clk              : in  std_logic;
      reset_sink_reset_n     : in  std_logic;
      adc_pll_clock_clk      : in  std_logic;
      adc_pll_locked_export  : in  std_logic;
      command_valid          : in  std_logic;
      command_channel        : in  std_logic_vector(4 downto 0);
      command_startofpacket  : in  std_logic;
      command_endofpacket    : in  std_logic;
      command_ready          : out std_logic;
      response_valid         : out std_logic;
      response_channel       : out std_logic_vector(4 downto 0);
      response_data          : out std_logic_vector(11 downto 0);
      response_startofpacket : out std_logic;
      response_endofpacket   : out std_logic
    );
  end component;

  signal cmd_valid : std_logic := '0';
  signal cmd_ch    : integer range 1 to 8 := 1;
  signal cmd_sop   : std_logic;
  signal cmd_eop   : std_logic;
  signal cmd_ready : std_logic;
  signal rsp_valid : std_logic;
  signal rsp_ch    : std_logic_vector(4 downto 0);
  signal rsp_data  : std_logic_vector(11 downto 0);

  signal store     : std_logic_vector(127 downto 0) := (others => '0');

begin

  adc_val <= store;

  cmd_valid <= adc_pll_lock;                 -- richiede campioni quando la PLL e' agganciata
  cmd_sop   <= '1' when cmd_ch = 1    else '0';
  cmd_eop   <= '1' when cmd_ch = N_CH else '0';

  u_adc : modular_adc
    port map (
      clock_clk              => clk,
      reset_sink_reset_n     => rst_n,
      adc_pll_clock_clk      => adc_pll_clk,
      adc_pll_locked_export  => adc_pll_lock,
      command_valid          => cmd_valid,
      command_channel        => std_logic_vector(to_unsigned(cmd_ch, 5)),
      command_startofpacket  => cmd_sop,
      command_endofpacket    => cmd_eop,
      command_ready          => cmd_ready,
      response_valid         => rsp_valid,
      response_channel       => rsp_ch,
      response_data          => rsp_data,
      response_startofpacket => open,
      response_endofpacket   => open
    );

  -- Sequenziamento comandi: avanza il canale ad ogni handshake accettato.
  process (clk)
    variable ch : integer range 0 to 8;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        cmd_ch <= 1;
        store  <= (others => '0');
      else
        if cmd_valid = '1' and cmd_ready = '1' then
          if cmd_ch = N_CH then cmd_ch <= 1; else cmd_ch <= cmd_ch + 1; end if;
        end if;

        -- Memorizza le risposte: canale c (1..N) -> slot c-1, esteso a 16 bit.
        if rsp_valid = '1' then
          ch := to_integer(unsigned(rsp_ch));
          if ch >= 1 and ch <= N_CH then
            store(16*(ch-1)+15 downto 16*(ch-1)) <= "0000" & rsp_data;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
