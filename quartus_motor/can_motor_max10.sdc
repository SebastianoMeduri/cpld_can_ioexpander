#===============================================================================
# can_motor_max10.sdc  --  vincoli di timing per la variante MOTORE (MAX 10)
#===============================================================================

# Clock di sistema del kit: 50 MHz (periodo 20 ns)
create_clock -name clk -period 20.000 [get_ports clk]

derive_clock_uncertainty

# Ingressi asincroni non critici a 500 kbit/s
set_false_path -from [get_ports {rst_n}] -to [all_registers]
set_false_path -from [get_ports {node_addr[*]}] -to [all_registers]
set_false_path -from [get_ports {safe_ch1 safe_ch2}] -to [all_registers]

# Uscite di controllo verso i driver (non critiche in timing rispetto al clock)
set_false_path -from [all_registers] -to [get_ports {mot[*]}]
set_false_path -from [all_registers] -to [get_ports {led_error led_alarm}]
