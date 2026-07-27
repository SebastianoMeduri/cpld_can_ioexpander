#===============================================================================
# assign_pins.tcl  --  Pinout MAX 10 (10M08SAE144C8G), ordinato/sequenziale.
#
# Criterio: pin assegnati in ordine CRESCENTE per gruppo, rispettando pero' la
# capacita' direzionale del pin. Sono usati solo pin gia' validati dal Fitter
# nell'auto-place (bidir per gli io, input per gli ingressi, clock per clk),
# quindi il fit e' garantito.
#
#   io[0..31]  -> 32 pin BIDIREZIONALI (ordinati)
#   ingressi   -> pin INPUT-capable (ordinati): rst_n, can_rxd, node_addr[*],
#                 safe_ch1/2, encoder A/B
#   clk        -> PIN_28 (ingresso di clock dedicato)
#   can_txd (PIN_59), led_error (PIN_57) -> uscite (pin scelti dal Fitter, ora fissi)
#
# USO (progetto can_ioexpander_max10 aperto):
#   View -> Tcl Console  ->  source assign_pins.tcl  ->  Start Compilation
# Board 3.3 V -> vedere AN 447 (resistore serie/clamp sugli I/O).
#===============================================================================

# Azzera eventuali assegnazioni di pin precedenti (rende lo script ripetibile
# ed evita conflitti da residui di run precedenti, es. can_txd/led_error).
remove_all_instance_assignments -name LOCATION

# --- Clock dedicato ---
set_location_assignment PIN_28  -to clk

# --- Ingressi di controllo (pin input-capable, ordinati) ---
set_location_assignment PIN_6   -to rst_n
set_location_assignment PIN_7   -to can_rxd            ;# da RXD transceiver CAN
set_location_assignment PIN_59  -to can_txd            ;# verso TXD transceiver CAN (uscita)
set_location_assignment PIN_57  -to led_error          ;# uscita
set_location_assignment PIN_15  -to {node_addr[0]}
set_location_assignment PIN_56  -to {node_addr[1]}
set_location_assignment PIN_61  -to {node_addr[2]}
set_location_assignment PIN_66  -to {node_addr[3]}
set_location_assignment PIN_70  -to safe_ch1           ;# pull-down esterno
set_location_assignment PIN_78  -to safe_ch2           ;# pull-down esterno

# --- Encoder A/B (pin input-capable, ordinati) ---
set_location_assignment PIN_79  -to {enc_a[0]}
set_location_assignment PIN_80  -to {enc_b[0]}
set_location_assignment PIN_81  -to {enc_a[1]}
set_location_assignment PIN_84  -to {enc_b[1]}
set_location_assignment PIN_85  -to {enc_a[2]}
set_location_assignment PIN_86  -to {enc_b[2]}
set_location_assignment PIN_87  -to {enc_a[3]}
set_location_assignment PIN_89  -to {enc_b[3]}
set_location_assignment PIN_90  -to {enc_a[4]}
set_location_assignment PIN_91  -to {enc_b[4]}
set_location_assignment PIN_105 -to {enc_a[5]}
set_location_assignment PIN_113 -to {enc_b[5]}
set_location_assignment PIN_123 -to {enc_a[6]}
set_location_assignment PIN_127 -to {enc_b[6]}
set_location_assignment PIN_131 -to {enc_a[7]}
set_location_assignment PIN_132 -to {enc_b[7]}

# --- io[0..31] (pin bidirezionali, ordinati) ---
set_location_assignment PIN_8   -to {io[0]}
set_location_assignment PIN_10  -to {io[1]}
set_location_assignment PIN_11  -to {io[2]}
set_location_assignment PIN_12  -to {io[3]}
set_location_assignment PIN_13  -to {io[4]}
set_location_assignment PIN_14  -to {io[5]}
set_location_assignment PIN_17  -to {io[6]}
set_location_assignment PIN_21  -to {io[7]}
set_location_assignment PIN_22  -to {io[8]}
set_location_assignment PIN_55  -to {io[9]}
set_location_assignment PIN_60  -to {io[10]}
set_location_assignment PIN_62  -to {io[11]}
set_location_assignment PIN_88  -to {io[12]}
set_location_assignment PIN_92  -to {io[13]}
set_location_assignment PIN_93  -to {io[14]}
set_location_assignment PIN_96  -to {io[15]}
set_location_assignment PIN_97  -to {io[16]}
set_location_assignment PIN_98  -to {io[17]}
set_location_assignment PIN_99  -to {io[18]}
set_location_assignment PIN_100 -to {io[19]}
set_location_assignment PIN_101 -to {io[20]}
set_location_assignment PIN_102 -to {io[21]}
set_location_assignment PIN_111 -to {io[22]}
set_location_assignment PIN_112 -to {io[23]}
set_location_assignment PIN_114 -to {io[24]}
set_location_assignment PIN_118 -to {io[25]}
set_location_assignment PIN_119 -to {io[26]}
set_location_assignment PIN_120 -to {io[27]}
set_location_assignment PIN_121 -to {io[28]}
set_location_assignment PIN_122 -to {io[29]}
set_location_assignment PIN_124 -to {io[30]}
set_location_assignment PIN_134 -to {io[31]}

# I/O standard 3.3-V LVTTL
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"

export_assignments
puts "======================================================================"
puts " Pinout MAX 10 ordinato applicato (59 pin fissi)"
puts " Ora: Processing -> Start Compilation"
puts "======================================================================"
