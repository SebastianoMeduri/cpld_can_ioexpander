#===============================================================================
# can_ioexpander.sdc  --  vincoli di timing (TimeQuest)
#===============================================================================

# Clock di sistema 20 MHz (periodo 50 ns)
create_clock -name clk -period 50.000 [get_ports clk]

derive_clock_uncertainty

# Ingressi/uscite asincroni verso il transceiver e i pin di I/O: non critici a
# 20 MHz. Impostazioni di base per evitare warning di percorsi non vincolati.
set_false_path -from [get_ports {rst_n}] -to [all_registers]
set_false_path -from [get_ports {node_addr[*]}] -to [all_registers]
