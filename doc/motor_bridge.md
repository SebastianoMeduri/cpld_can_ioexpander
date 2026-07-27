# Variante MOTORE — 8 driver VNH7100AS

Specializzazione della piattaforma per pilotare **8 half/full-bridge STMicro
VNH7100AS** via CAN, con controllo di velocità **PWM**, direzione, frenata e
lettura della **corrente MultiSense** con soglie di **sovracorrente**.

Riusa il controller CAN, la funzione di sicurezza a doppio canale e l'ADC del
MAX 10 già presenti; aggiunge un generatore PWM a 8 canali e un livello
applicativo dedicato. Target: **MAX 10** (serve l'ADC per il MultiSense).

## Moduli RTL

| File | Ruolo |
|------|-------|
| [../rtl/pwm_gen.vhd](../rtl/pwm_gen.vhd) | PWM a canale singolo, prescaler + caso fondoscala (ON statico) |
| [../rtl/motor_expander.vhd](../rtl/motor_expander.vhd) | livello applicativo motore (comando, PWM ×8, sicurezza, telemetria) |
| [../rtl/can_motor_top.vhd](../rtl/can_motor_top.vhd) | top: `can_controller` + `motor_expander` |
| [../rtl/can_motor_max10.vhd](../rtl/can_motor_max10.vhd) | wrapper MAX 10 (50 MHz, 500 kbit/s, PWM ~19,5 kHz, ADC on) |

Simulazione: [../sim/run_ghdl_motor.ps1](../sim/run_ghdl_motor.ps1) /
[.sh](../sim/run_ghdl_motor.sh) → testbench
[../sim/tb_can_motor.vhd](../sim/tb_can_motor.vhd) (validato, *TUTTI I TEST SUPERATI*).

## Collegamento ai driver

Le 32 uscite `mot[]` mappano gli 8 driver, raggruppate per funzione:

| Bit `mot[]` | Segnale VNH7100AS | Note |
|-------------|-------------------|------|
| `7..0`   | `INA(0..7)`   | direzione A |
| `15..8`  | `INB(0..7)`   | direzione B |
| `23..16` | `PWM(0..7)`   | modulazione (≤ ~20 kHz) |
| `31..24` | `SEL0(0..7)`  | selezione MultiSense (valore comune configurabile) |
| ADC ch i | `MultiSense(i)` | corrente/diagnostica del driver i → ADC MAX 10 |

Tabella di comando per motore (mode a 2 bit):

| mode | Nome | INA | INB | PWM | Effetto |
|------|------|-----|-----|-----|---------|
| `00` | COAST | 0 | 0 | 0 | ponte in alta impedenza (ruota libera) |
| `01` | FWD   | 1 | 0 | duty | avanti |
| `10` | REV   | 0 | 1 | duty | indietro |
| `11` | BRAKE | 0 | 0 | 1 | frenata a GND |

Il **duty** è a 6 bit (0..63): `0` = fermo, `63` = **fondoscala** → PWM statico
alto = controllo **ON/OFF**; i valori intermedi danno il controllo di velocità.

## PWM

`f_pwm = f_clk / (PWM_PRESCALE · 2^6)`. Sul MAX 10 (50 MHz, `PWM_PRESCALE=40`) →
**~19,5 kHz**, entro il limite del VNH7100AS. Per cambiare frequenza si agisce sul
generic `PWM_PRESCALE` nel wrapper.

## Protocollo CAN (ID = FUNC & NODE & SUB)

| FUNC | Nome | Dir | Contenuto |
|------|------|-----|-----------|
| `000` | PERIOD  | host→exp | `data[63:48]` = periodo telemetria correnti (ms, 0=off) |
| `001` | MOTOR   | host→exp | DLC=8, byte k = motore k: `[7:6]`=mode, `[5:0]`=duty |
| `010` | CONFIG  | host→exp | SUB=0: byte0 `bit0`=safe_mode (0=coast,1=brake), `bit1`=SEL0; SUB=1/2: soglie corrente (uint16 12 bit) |
| `011` | REQUEST | host→exp | invio immediato dello STATUS |
| `100` | STATUS  | exp→host | byte0 `bit0`=safe_ok, `bit1`=safe_mode, `bit2`=SEL0; byte1 = bitmap sovracorrente |
| `111` | ANALOG  | exp→host | correnti MultiSense (SUB=0 ch0..3, SUB=1 ch4..7); SUB=2 = bitmap sovracorrente (`data[63:56]`) |

Il **bitmap sovracorrente** (bit i = `corrente(i) ≥ soglia(i)`) è inviato in coda
alla telemetria periodica **e subito al variare**, come allarme. Le soglie sono a
fondo scala (0xFFF) al reset → nessun allarme finché non le si configura. Il
VNH7100AS ha protezioni interne (sovracorrente/sovratemperatura): la soglia lato
CPLD serve per **segnalazione/policy**, non come protezione primaria.

## Diagnostica (LED)

Due uscite LED attive-alte (3,3 V LVTTL, resistore di serie + AN 447):

| LED | Pin (kit) | Acceso quando |
|-----|-----------|---------------|
| `led_error` | 57 | fault persistente del **bus CAN** (error-passive o bus-off); si rispegne al recupero |
| `led_alarm` | 79 | **sovracorrente** su almeno un motore (OR del bitmap `corrente(i) ≥ soglia(i)`) |

`led_alarm` segue in tempo reale il bitmap di sovracorrente (lo stesso inviato con
ANALOG SUB=2). È a riposo (spento) finché le soglie non sono configurate, perché al
reset valgono fondo scala.

## Sicurezza (doppio canale fail-safe)

Se manca il consenso (`safe_ch1`/`safe_ch2`, attivi alti) tutti i motori vanno
allo **stato sicuro configurabile**:

* **COAST** (default): `INA=INB=PWM=0` → ruota libera;
* **BRAKE**: `INA=INB=0, PWM=1` → frenata a GND.

Ripristino automatico al ritorno del consenso. Prevedere pull-down esterni sui due
ingressi (loss-of-signal → stato sicuro).

## Note elettriche / PCB

* **Logica**: gli ingressi VNH7 hanno soglia `V_IH` ~2 V e sono 5 V-tolerant → i
  3,3 V del MAX 10 li pilotano direttamente (verificare `V_IH` sul datasheet).
* **MultiSense**: è una **sorgente di corrente** → resistore di sense verso GND
  dimensionato perché il fondo scala corrente (e il valore di fault, tensione alta
  fissa) restino entro il range dell'ADC (0..~3,0 V). Vale AN 447 per i 3,3 V.
* **SEL0** può essere reso comune a tutti i driver (già gestito come valore unico).
* **Alimentazione di potenza** (batteria/carico) separata dalla logica; decoupling
  e dissipazione secondo il datasheet VNH7100AS.

## Quartus (MAX 10)

Progetto pronto in **`quartus_motor/`** (top = `can_motor_max10`), sorgenti:
`can_pkg`, `can_bit_timing`, `can_mac`, `can_controller`, `pwm_gen`,
`motor_expander`, `can_motor_top`, `can_motor_max10`. Pinout in
`quartus_motor/assign_pins.tcl` (o già nel `.qsf`): 44 pin fissi, le 32 uscite
`mot[]` sui pin bidir del 10M08 (INA 8..21, INB 22..96, PWM 97..112, SEL0 114..134),
CAN/safety/clock come gli altri target, LED `led_error`=57 e `led_alarm`=79.

**Compilazione confermata (Quartus 25.1 Lite):** 0 errori, **1.185/8.064 LE (~15%)**,
setup slack **+10,3 ns @ 50 MHz**, 183 mW, pinout accettato dal Fitter. L'unico
warning di sintesi (`adc_val ... never assigned`) è atteso: le correnti sono a 0
finché non si genera l'IP ADC.

**Correnti reali (MultiSense):** generare in Quartus l'IP "Altera Modular ADC Core"
+ PLL, aggiungere `../rtl/adc_reader.vhd` + l'IP al progetto (righe già predisposte,
commentate, nel `.qsf`) e collegare `adc_reader.adc_val` al segnale `adc_val` in
`can_motor_max10` (vedi [MANUALE.md](MANUALE.md)).
