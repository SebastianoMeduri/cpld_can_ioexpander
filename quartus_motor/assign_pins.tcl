#===============================================================================
# assign_pins.tcl  --  Pinout variante MOTORE su MAX 10 (10M08SAE144C8G).
#
# Le 32 uscite mot[] pilotano gli 8 driver VNH7100AS, raggruppate per funzione:
#   mot[7:0]   = INA(0..7)   (direzione A)
#   mot[15:8]  = INB(0..7)   (direzione B)
#   mot[23:16] = PWM(0..7)   (modulazione, <= ~20 kHz)
#   mot[31:24] = SEL0(0..7)  (selezione MultiSense, valore comune)
# Le correnti MultiSense entrano dall'ADC interno (pin gestiti dall'IP, non qui).
#
# Sono usati solo pin gia' validati dal Fitter (bidir/output-capable per mot[],
# input-capable per gli ingressi, clock per clk) -> il fit e' garantito.
#
# USO (progetto can_motor_max10 aperto):
#   View -> Tcl Console  ->  source assign_pins.tcl  ->  Start Compilation
# Board 3.3 V -> vedere AN 447 (resistore serie/clamp sugli I/O).
#===============================================================================

# Azzera assegnazioni di pin precedenti (script ripetibile, niente residui)
remove_all_instance_assignments -name LOCATION

# --- Clock dedicato ---
set_location_assignment PIN_28  -to clk

# --- Ingressi/uscite di controllo ---
set_location_assignment PIN_6   -to rst_n
set_location_assignment PIN_7   -to can_rxd            ;# da RXD transceiver CAN
set_location_assignment PIN_59  -to can_txd            ;# verso TXD transceiver CAN
set_location_assignment PIN_57  -to led_error          ;# uscita LED fault bus CAN
set_location_assignment PIN_79  -to led_alarm          ;# uscita LED allarme sovracorrente motori
set_location_assignment PIN_15  -to {node_addr[0]}
set_location_assignment PIN_56  -to {node_addr[1]}
set_location_assignment PIN_61  -to {node_addr[2]}
set_location_assignment PIN_66  -to {node_addr[3]}
set_location_assignment PIN_70  -to safe_ch1           ;# consenso, pull-down esterno
set_location_assignment PIN_78  -to safe_ch2           ;# consenso, pull-down esterno

# --- INA(0..7) = mot[7:0] ---
set_location_assignment PIN_8   -to {mot[0]}
set_location_assignment PIN_10  -to {mot[1]}
set_location_assignment PIN_11  -to {mot[2]}
set_location_assignment PIN_12  -to {mot[3]}
set_location_assignment PIN_13  -to {mot[4]}
set_location_assignment PIN_14  -to {mot[5]}
set_location_assignment PIN_17  -to {mot[6]}
set_location_assignment PIN_21  -to {mot[7]}
# --- INB(0..7) = mot[15:8] ---
set_location_assignment PIN_22  -to {mot[8]}
set_location_assignment PIN_55  -to {mot[9]}
set_location_assignment PIN_60  -to {mot[10]}
set_location_assignment PIN_62  -to {mot[11]}
set_location_assignment PIN_88  -to {mot[12]}
set_location_assignment PIN_92  -to {mot[13]}
set_location_assignment PIN_93  -to {mot[14]}
set_location_assignment PIN_96  -to {mot[15]}
# --- PWM(0..7) = mot[23:16] ---
set_location_assignment PIN_97  -to {mot[16]}
set_location_assignment PIN_98  -to {mot[17]}
set_location_assignment PIN_99  -to {mot[18]}
set_location_assignment PIN_100 -to {mot[19]}
set_location_assignment PIN_101 -to {mot[20]}
set_location_assignment PIN_102 -to {mot[21]}
set_location_assignment PIN_111 -to {mot[22]}
set_location_assignment PIN_112 -to {mot[23]}
# --- SEL0(0..7) = mot[31:24] ---
set_location_assignment PIN_114 -to {mot[24]}
set_location_assignment PIN_118 -to {mot[25]}
set_location_assignment PIN_119 -to {mot[26]}
set_location_assignment PIN_120 -to {mot[27]}
set_location_assignment PIN_121 -to {mot[28]}
set_location_assignment PIN_122 -to {mot[29]}
set_location_assignment PIN_124 -to {mot[30]}
set_location_assignment PIN_134 -to {mot[31]}

# I/O standard 3.3-V LVTTL
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"

export_assignments
puts "======================================================================"
puts " Pinout MAX 10 variante MOTORE applicato (44 pin fissi)"
puts " Ora: Processing -> Start Compilation"
puts "======================================================================"
