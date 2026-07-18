# cpld_can_ioexpander

I/O expander su **CAN bus** implementato in **VHDL**, sintetizzabile su CPLD/FPGA.
Il dispositivo integra un controller CAN 2.0A completo (protocollo interamente in
VHDL, pilota solo un transceiver PHY) e un espansore di **32 pin bidirezionali**
configurabili singolarmente come ingresso o uscita e comandabili via CAN.

## Caratteristiche

- Controller **CAN 2.0A** (identificatore standard 11 bit) scritto in VHDL:
  bit timing, bit stuffing/de-stuffing, CRC-15, arbitraggio, ACK,
  ritrasmissione automatica.
- **Gestione errori e fault confinement** (ISO 11898-1, semplificato): bit/stuff/
  form/ACK/CRC error, error frame attivi e passivi, contatori TEC/REC e stati
  error-active / error-passive / bus-off con recupero.
- **CAN 2.0B passive**: tollera e conferma le trame a identificatore esteso
  (29 bit) senza consegnarle all'applicazione (compatibilita' reti miste).
- Risincronizzazione con correzione dell'errore di fase in entrambe le direzioni
  (tolleranza di clock).
- **Funzione di sicurezza a doppio canale (fail-safe)**: due ingressi di consenso
  (`safe_ch1`, `safe_ch2`); se uno qualsiasi va basso le uscite vengono forzate a
  livello basso, con auto-ripristino e notifica STATUS.
- **32 pin bidirezionali**, direzione configurabile per singolo pin.
- Invio dello stato **su richiesta** e **automatico** al variare di un ingresso.
- Default: **500 kbit/s** con clock a **20 MHz** (parametrizzabile via `generic`).
- Codice **VHDL portabile e vendor-neutral** (nessuna dipendenza da primitive
  proprietarie), piu' testbench end-to-end.

## Struttura del progetto

```
rtl/
  can_pkg.vhd            Funzioni comuni (CRC-15, utilita')
  can_bit_timing.vhd     Temporizzazione di bit (time quanta, sync/resync)
  can_mac.vhd            Livello MAC CAN 2.0A (TX/RX in un'unica FSM)
  can_controller.vhd     Sincronizzatore + bit timing + MAC (interfaccia a messaggi)
  io_expander.vhd        Logica dell'espansore I/O a 32 pin
  can_ioexpander_top.vhd Top level (controller + espansore)
sim/
  tb_can_ioexpander.vhd  Testbench end-to-end (host + DUT su bus wired-AND)
  run_ghdl.sh            Script di simulazione GHDL (Linux/macOS/Git Bash)
  run_ghdl.ps1           Script di simulazione GHDL (Windows PowerShell)
doc/
  protocol.md            Descrizione del protocollo applicativo
```

Ordine di compilazione: `can_pkg` -> `can_bit_timing` -> `can_mac` ->
`can_controller` -> `io_expander` -> `can_ioexpander_top` -> testbench.

## Interfaccia hardware (top level)

| Segnale       | Dir   | Descrizione                                  |
|---------------|-------|----------------------------------------------|
| `clk`         | in    | clock di sistema (20 MHz di default)         |
| `rst_n`       | in    | reset asincrono attivo basso                 |
| `can_rxd`     | in    | RXD dal transceiver CAN (0 = dominante)      |
| `can_txd`     | out   | TXD verso il transceiver CAN (0 = dominante) |
| `node_addr`   | in    | indirizzo nodo, 4 bit (es. da dip-switch)    |
| `safe_ch1`    | in    | sicurezza, canale 1 (consenso attivo alto)   |
| `safe_ch2`    | in    | sicurezza, canale 2 (consenso attivo alto)   |
| `io[31:0]`    | inout | 32 pin di I/O bidirezionali                  |
| `led_error`   | out   | diagnostica: LED su fault CAN persistente    |

Il core va collegato a un transceiver CAN fisico (es. **TJA1050**,
**SN65HVD230**, **MCP2551**): `can_txd` -> TXD, `can_rxd` <- RXD.

## Protocollo

Vedere [doc/protocol.md](doc/protocol.md). In sintesi, l'ID a 11 bit e'
`FUNC(3) & NODE(4) & 0000` con le funzioni CONFIG / OUTPUT / REQUEST / STATUS.

## Simulazione

Richiede [GHDL](https://ghdl.github.io) (VHDL-2008).

```bash
# Linux / macOS / Git Bash
bash sim/run_ghdl.sh
```

```powershell
# Windows PowerShell
powershell -File sim\run_ghdl.ps1
```

Il testbench collega un nodo host e il DUT sullo stesso bus e verifica la
sequenza CONFIG -> OUTPUT -> lettura uscite -> STATUS automatico su variazione
di un ingresso. In caso di successo stampa `*** TUTTI I TEST SUPERATI ***`.

## Sintesi

Il codice e' RTL portabile e non usa primitive specifiche del vendor: puo'
essere importato in Quartus, Vivado/ISE, Lattice Diamond, ecc. Occorre
aggiungere il proprio file di vincoli (pinout e clock) per il dispositivo
scelto e mappare i pin `io[31:0]` su I/O bidirezionali reali.

> Nota sulla capienza: un controller CAN completo piu' 32 I/O richiede una
> discreta quantita' di logica. Verificare che il dispositivo target abbia
> risorse sufficienti (un CPLD molto piccolo potrebbe non bastare; sono adatti
> CPLD ampi o piccole FPGA come MAX 10 / MachXO2 / Spartan).

## Stato dei test

- **Sintesi/fitting** (Quartus Prime Lite 21.1, MAX V 5M1270ZT144): 0 errori,
  timing rispettato, pinout assegnato.
- **Simulazione funzionale** (GHDL): il testbench in `sim/` valida
  CONFIG → OUTPUT → STATUS, l'iniezione di un errore con relativo recupero
  (error frame + ritorno operativo) e la tolleranza di una trama a
  identificatore esteso (2.0B passive). Tutti i test superati.

Le limitazioni residue del core sono elencate in [doc/protocol.md](doc/protocol.md).
