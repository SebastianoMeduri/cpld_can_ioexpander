#===============================================================================
# assign_pins.tcl
# Applica il pinout dell'I/O expander (MAX V 5M1270Z, package T144) al progetto
# Quartus corrente, usando l'API di Quartus (evita il conflitto con il .qsf
# tenuto aperto dalla GUI).
#
# USO (con il progetto can_ioexpander APERTO in Quartus):
#   1) View -> Tcl Console   (oppure Tools -> Tcl Console)
#   2) nella console:   source assign_pins.tcl
#   3) poi:  Processing -> Start Compilation
#
# I nomi di bus sono racchiusi in { } per evitare la sostituzione di comando
# del Tcl (io[0] senza graffe verrebbe interpretato male dalla console).
#===============================================================================

# --- Banco 1: controllo / comunicazione ---
set_location_assignment PIN_18  -to clk            ;# global clock input dedicato
set_location_assignment PIN_16  -to rst_n
set_location_assignment PIN_20  -to can_rxd        ;# da RXD del transceiver CAN
set_location_assignment PIN_21  -to can_txd        ;# verso TXD del transceiver CAN
set_location_assignment PIN_22  -to {node_addr[0]}
set_location_assignment PIN_23  -to {node_addr[1]}
set_location_assignment PIN_24  -to {node_addr[2]}
set_location_assignment PIN_27  -to {node_addr[3]}
set_location_assignment PIN_28  -to led_error

# --- io[0..31] raggruppati su pin contigui 73..111 (banchi 3 e 2) ---
set_location_assignment PIN_73  -to {io[0]}
set_location_assignment PIN_74  -to {io[1]}
set_location_assignment PIN_75  -to {io[2]}
set_location_assignment PIN_76  -to {io[3]}
set_location_assignment PIN_77  -to {io[4]}
set_location_assignment PIN_79  -to {io[5]}
set_location_assignment PIN_80  -to {io[6]}
set_location_assignment PIN_81  -to {io[7]}
set_location_assignment PIN_84  -to {io[8]}
set_location_assignment PIN_85  -to {io[9]}
set_location_assignment PIN_86  -to {io[10]}
set_location_assignment PIN_87  -to {io[11]}
set_location_assignment PIN_88  -to {io[12]}
set_location_assignment PIN_89  -to {io[13]}
set_location_assignment PIN_91  -to {io[14]}
set_location_assignment PIN_93  -to {io[15]}
set_location_assignment PIN_94  -to {io[16]}
set_location_assignment PIN_95  -to {io[17]}
set_location_assignment PIN_96  -to {io[18]}
set_location_assignment PIN_97  -to {io[19]}
set_location_assignment PIN_98  -to {io[20]}
set_location_assignment PIN_101 -to {io[21]}
set_location_assignment PIN_102 -to {io[22]}
set_location_assignment PIN_103 -to {io[23]}
set_location_assignment PIN_104 -to {io[24]}
set_location_assignment PIN_105 -to {io[25]}
set_location_assignment PIN_106 -to {io[26]}
set_location_assignment PIN_107 -to {io[27]}
set_location_assignment PIN_108 -to {io[28]}
set_location_assignment PIN_109 -to {io[29]}
set_location_assignment PIN_110 -to {io[30]}
set_location_assignment PIN_111 -to {io[31]}

# --- I/O standard di default: 3.3-V LVTTL su tutti i banchi ---
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"

# Scrive le assegnazioni nel .qsf del progetto
export_assignments
puts "======================================================================"
puts " Pinout applicato (41 pin). Ora lancia: Processing -> Start Compilation"
puts "======================================================================"
