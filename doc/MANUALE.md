# Manuale della piattaforma — CAN I/O Expander

Documentazione tecnica completa del progetto **cpld_can_ioexpander**: un
espansore di I/O su CAN bus, con controller CAN 2.0A completo in VHDL, funzione
di sicurezza a doppio canale e lettura di 8 encoder incrementali, sintetizzabile
sia su CPLD **MAX V** sia su FPGA **MAX 10**, corredato di driver **ESP32** e
**GUI di test C#** (PEAK PCAN-USB).

> Documento di riferimento. Per il solo protocollo applicativo vedere
> [protocol.md](protocol.md); per la scheda di sintesi visuale vedere il report
> tecnico ([technical_report.html](technical_report.html)).

---

## Indice

1. [Panoramica](#1-panoramica)
2. [Architettura](#2-architettura)
3. [Moduli RTL](#3-moduli-rtl)
4. [Parametri (generic)](#4-parametri-generic)
5. [Protocollo CAN applicativo](#5-protocollo-can-applicativo)
6. [Funzione di sicurezza](#6-funzione-di-sicurezza)
7. [Encoder incrementali](#7-encoder-incrementali)
8. [Gestione errori e fault confinement](#8-gestione-errori-e-fault-confinement)
9. [Target di sintesi e risultati](#9-target-di-sintesi-e-risultati)
10. [Pinout](#10-pinout)
11. [Simulazione](#11-simulazione)
12. [Compilazione e programmazione](#12-compilazione-e-programmazione)
13. [Note di progetto della scheda](#13-note-di-progetto-della-scheda)
14. [Strumenti host](#14-strumenti-host)
15. [Limitazioni note](#15-limitazioni-note)
16. [Struttura del repository](#16-struttura-del-repository)

---

## 1. Panoramica

Il dispositivo si collega a un bus CAN tramite un transceiver PHY esterno e mette
a disposizione:

- **32 pin bidirezionali** configurabili singolarmente come ingresso o uscita,
  comandabili e leggibili via messaggi CAN;
- **funzione di sicurezza a doppio canale** che forza le uscite a livello basso;
- **8 encoder incrementali** in quadratura (A/B), con conteggio e trasmissione
  periodica su CAN.

Il protocollo CAN è implementato interamente nella logica programmabile: bit
timing, bit stuffing, CRC-15, arbitraggio, ACK, error frame e fault confinement.
Non serve alcun microcontrollore né controller CAN dedicato.

| Caratteristica | Valore |
|---|---|
| Standard CAN | 2.0A (11 bit) + 2.0B passive (tollera 29 bit) |
| Bitrate | 500 kbit/s (parametrizzabile) |
| Clock di sistema | 20 MHz (MAX V) / 50 MHz (MAX 10) |
| I/O bidirezionali | 32, direzione per singolo pin |
| Encoder | 8 × quadratura A/B, contatore 16 bit con segno |
| Ingressi analogici | 8 canali via ADC 12 bit (solo MAX 10) |
| Sicurezza | doppio canale fail-safe (uscite a low) |
| Codice | VHDL-2008 portabile, vendor-neutral |

---

## 2. Architettura

```
                         ┌───────────────────────────────────────────┐
   clk, rst_n ──────────▶│ can_ioexpander_top                        │
                         │  ┌───────────────┐   ┌──────────────────┐ │
   can_rxd ─────────────▶│  │ can_controller│◀─▶│  io_expander     │ │──▶ io[31:0]
   can_txd ◀─────────────│  │  (sync+timing │   │  - 32 I/O        │ │
                         │  │   + MAC)      │   │  - sicurezza     │◀── safe_ch1/2
   node_addr[3:0] ──────▶│  └───────────────┘   │  - scheduler TX  │ │
                         │        ▲              │  - encoder mgmt  │ │
   enc_a[7:0] ──┐        │        │              └──────────────────┘ │
   enc_b[7:0] ──┼───────▶│  ┌───────────────┐            ▲            │
                │        │  │ 8× quad_decoder│────────────┘ enc_count  │
                └────────│  └───────────────┘                         │
                         │                              led_error ────┼──▶
                         └───────────────────────────────────────────┘
```

Gerarchia:

```
can_ioexpander_top
├── can_controller
│   ├── (sincronizzatore 2FF del bus)
│   ├── can_bit_timing
│   └── can_mac
├── quad_decoder  × 8
└── io_expander
```

Sul target MAX 10 il top è avvolto da `can_ioexpander_max10` (wrapper che fissa i
generic per il clock a 50 MHz).

---

## 3. Moduli RTL

| File | Entità | Funzione |
|---|---|---|
| `rtl/can_pkg.vhd` | `can_pkg` | Funzioni comuni: CRC-15 (`crc15_next`, poly 0x4599), `min2` |
| `rtl/can_bit_timing.vhd` | `can_bit_timing` | Time quanta, sample point, hard sync + resync (entrambe le direzioni) |
| `rtl/can_mac.vhd` | `can_mac` | Livello MAC: FSM unica TX/RX, stuffing, CRC, arbitraggio, ACK, error frame, TEC/REC |
| `rtl/can_controller.vhd` | `can_controller` | Sincronizzatore + bit timing + MAC; interfaccia a messaggi |
| `rtl/quad_decoder.vhd` | `quad_decoder` | Decodifica quadratura x4, contatore 16 bit con segno |
| `rtl/io_expander.vhd` | `io_expander` | 32 I/O, sicurezza, encoder, scheduler di trasmissione |
| `rtl/can_ioexpander_top.vhd` | `can_ioexpander_top` | Top level (controller + 8 encoder + io_expander) |
| `rtl/can_ioexpander_maxv.vhd` | `can_ioexpander_maxv` | Wrapper per MAX V (20 MHz, senza ADC) |
| `rtl/can_ioexpander_max10.vhd` | `can_ioexpander_max10` | Wrapper per MAX 10 (50 MHz) |
| `rtl/adc_reader.vhd` | `adc_reader` | Front-end ADC MAX 10 (8 canali) — richiede l'IP Modular ADC |

**Ordine di compilazione:** `can_pkg` → `can_bit_timing` → `can_mac` →
`can_controller` → `quad_decoder` → `io_expander` → `can_ioexpander_top`
→ (`can_ioexpander_max10`).

### Interfaccia del can_controller (a messaggi)

- **TX:** `tx_request`, `tx_id[10:0]`, `tx_rtr`, `tx_dlc[3:0]`, `tx_data[63:0]`,
  `tx_busy`, `tx_done`.
- **RX:** `rx_valid`, `rx_id[10:0]`, `rx_rtr`, `rx_dlc[3:0]`, `rx_data[63:0]`.
- **Stato:** `error_flag`, `error_passive`, `bus_off`, `tec_value[7:0]`.

I dati sono vettori a 64 bit (8 byte), byte0 = bit 63..56.

---

## 4. Parametri (generic)

Su `can_ioexpander_top`:

| Generic | Default | Descrizione |
|---|---|---|
| `BRP` | 2 | Prescaler bit timing (cicli clk per Tq) |
| `TSEG1` | 15 | Time quanta prima del sample point |
| `TSEG2` | 4 | Time quanta dopo il sample point |
| `SJW` | 3 | Ampiezza massima di risincronizzazione (Tq) |
| `MS_TICKS` | 20000 | Cicli di clk per 1 ms (base tempi encoder) |
| `ENC_PERIOD_MS` | 10 | Periodo TX encoder in ms (0 = off) |

**Relazione bit timing:** `1 bit = (1 + TSEG1 + TSEG2) × Tq = 1/bitrate`, con
`Tq = BRP / f_clk`. Sample point = `(1 + TSEG1)/(1 + TSEG1 + TSEG2)`.

| Clock | BRP | Tq | bit | bitrate | MS_TICKS |
|---|---|---|---|---|---|
| 20 MHz (MAX V) | 2 | 100 ns | 2 µs | 500 kbit/s | 20000 |
| 50 MHz (MAX 10) | 5 | 100 ns | 2 µs | 500 kbit/s | 50000 |

In entrambi i casi: 20 Tq/bit, **sample point all'80 %**, SJW = 3.

---

## 5. Protocollo CAN applicativo

Identificatore a 11 bit: `ID = FUNC(3) & NODE(4) & SUB(4)`.

| FUNC | Nome | Dir. | Descrizione |
|---|---|---|---|
| `000` | ENC_PERIOD | host→exp | periodo TX encoder in ms: `data[63:48]` (0 = off) |
| `001` | OUTPUT | host→exp | `data[63:32]` = valori uscite; con DLC=8 `data[31:0]` = maschera |
| `010` | CONFIG | host→exp | `data[63:32]` = maschera direzione (1 = uscita) |
| `011` | REQUEST | host→exp | richiede invio immediato di STATUS |
| `100` | STATUS | exp→host | `data[63:32]` = stato dei pin |
| `101` | ENC_RESET | host→exp | `data[7:0]` bitmask: bit i azzera l'encoder i |
| `110` | ENC_DATA | exp→host | conteggi encoder; SUB=0 → enc0..3, SUB=1 → enc4..7 |
| `111` | ANALOG | exp→host | letture ADC (solo MAX 10); SUB=0 → ch0..3, SUB=1 → ch4..7 |

I FUNC dei comandi host→exp sono più bassi di ENC_DATA/ANALOG, così l'host vince
l'arbitraggio anche durante la trasmissione periodica.

**Mappatura payload → pin** (CONFIG/OUTPUT/STATUS): il pin `i` è il bit `32+i`
della trama a 64 bit. Byte0 (`data[63:56]`) = pin 31..24 … Byte3 = pin 7..0.

**ID di esempio (NODE = 0001):** ENC_PERIOD `0x010`, OUTPUT `0x110`,
CONFIG `0x210`, REQUEST `0x310`, STATUS `0x410`, ENC_RESET `0x510`,
ENC_DATA `0x610`/`0x611`.

Lo **STATUS** è inviato: su REQUEST, al variare di un ingresso, e ad ogni
transizione della sicurezza. Riporta il valore **effettivo** delle uscite
(forzato a 0 se la sicurezza è intervenuta) e il valore letto per gli ingressi.

---

## 6. Funzione di sicurezza

Doppio canale **fail-safe**: due ingressi di consenso attivi-alti `safe_ch1`,
`safe_ch2` (sincronizzati a 2FF).

- Le uscite sono abilitate **solo se entrambi** i consensi sono alti
  (`safe_ok = safe_ch1 AND safe_ch2`).
- Se uno qualsiasi va basso (E-stop, filo interrotto, mancanza segnale) **tutte
  le uscite sono forzate a livello basso** (override combinatorio, indipendente
  dai comandi CAN).
- **Auto-ripristino:** le uscite tornano ai valori comandati appena il consenso
  ritorna.
- Ogni transizione della sicurezza genera una trama **STATUS**.

> Board: prevedere **pull-down esterni** sui due ingressi, così che la perdita
> di segnale porti allo stato sicuro (uscite low).

Livello: funzione di sicurezza funzionale a doppio canale a livello logico. Per
una certificazione formale (ISO 13849 / IEC 61508) servono anche diagnostica di
discordanza tra canali, test periodici e analisi a livello di sistema.

---

## 7. Encoder incrementali

- **8 encoder** in quadratura A/B (`enc_a[7:0]`, `enc_b[7:0]`), sincronizzati a
  2FF, decodifica **x4** (conta su ogni transizione valida).
- **Contatore 16 bit con segno** per encoder (range −32768…+32767; wrap gestito
  lato host o con lettura frequente).
- Sequenze: avanti `00→01→11→10→00` (+1), indietro `00→10→11→01→00` (−1);
  transizioni doppie/illegali ignorate.

**Trasmissione (ENC_DATA, DLC=8):** due trame periodiche —
`SUB=0` → enc0..3, `SUB=1` → enc4..7. In ogni trama 4 × `int16`, encoder di indice
più basso nei byte più significativi: `data[63:48]=enc(k)`, `[47:32]=enc(k+1)`,
`[31:16]=enc(k+2)`, `[15:0]=enc(k+3)`.

- **ENC_PERIOD:** imposta il periodo di trasmissione (ms, `data[63:48]`); 0 = off.
- **ENC_RESET:** `data[7:0]` bitmask, bit i azzera il contatore dell'encoder i.

---

## 7-bis. Ingressi analogici (solo MAX 10)

Il MAX 10 10M08SA integra un **ADC SAR 12 bit** (~1 MSPS). L'expander può leggere
**8 canali analogici** e trasmetterli con il messaggio **ANALOG** (FUNC=111,
DLC=8), con la stessa cadenza periodica degli encoder:

- **SUB=0** → canali 0..3, **SUB=1** → canali 4..7;
- 4 × `uint16` per trama (12 bit utili, giustificati a destra), canale più basso
  nei byte più significativi (`data[63:48]=ch(k)` …).

Sul MAX V (CPLD senza ADC) il messaggio ANALOG è assente. La funzione è
controllata dal generic `ADC_PRESENT` (false = disabilitata, nessun impatto).

### Soglie configurabili e confronto

Ogni canale ha un **registro di soglia 12 bit** impostabile via CAN con il
messaggio **CONFIG** (`SUB=1` per ch0..3, `SUB=2` per ch4..7, DLC=8, stesso
ordinamento delle letture). L'expander confronta di continuo `adc[i]` con
`soglia[i]` e produce un **bitmap a 8 bit** (`over[i] = adc[i] >= soglia[i]`),
trasmesso con **ANALOG `SUB=2`** (`data[63:56]`) sia in coda alla sequenza
periodica sia **immediatamente al variare** del bitmap — un vero comparatore/
allarme analogico, analogo allo STATUS per gli ingressi digitali. Al reset le
soglie sono a fondo scala (0xFFF), quindi nessun allarme prima della configurazione.
Dettagli e formato in [protocol.md](protocol.md).

### Abilitazione dell'ADC sul target MAX 10

L'ADC è un **hard-IP** del MAX 10: va generato in Quartus (non è simulabile in
GHDL né presente sul MAX V). Il modulo [rtl/adc_reader.vhd](../rtl/adc_reader.vhd)
fa da sequencer (legge gli 8 canali → `adc_val`). Passi:

1. **IP Catalog → Altera Modular ADC Core**: variante con sequencer standard e
   interfaccia comandi/risposte, abilita fino a 8 canali (CH1..CH8), clock ADC da
   PLL. Annota il nome dell'entità generata e adegua il `component modular_adc` in
   `adc_reader.vhd`.
2. **IP Catalog → Altera PLL**: 50 MHz → clock ADC (es. 10 MHz); collega `locked`.
3. Aggiungi i file IP + `adc_reader.vhd` al progetto `quartus_max10`.
4. In `can_ioexpander_max10` imposta `ADC_PRESENT => true` e istanzia `adc_reader`,
   collegando la sua uscita `adc_val` al top:

   ```vhdl
   u_adc : entity work.adc_reader
     port map (clk => clk, rst_n => rst_n,
               adc_pll_clk => adc_clk, adc_pll_lock => adc_locked,
               adc_val => adc_val_s);
   -- e nel generic map del top:  ADC_PRESENT => true,
   -- nella port map del top:     adc_val => adc_val_s
   ```

I pin analogici sono pin dedicati/dual-purpose gestiti dall'IP (assegnati nella
configurazione dell'IP, non come porte RTL). Sui segnali 3.3 V vale AN 447.

## 8. Gestione errori e fault confinement

Conforme (in forma semplificata) a ISO 11898-1.

**Rilevazione errori:** bit error, stuff error, form error (delimitatori e EOF),
ACK error (trasmettitore), CRC error (ricevitore).

**Error frame:** flag *attivo* (6 bit dominanti) se error-active, flag *passivo*
(6 bit recessivi) se error-passive, seguito da error delimiter (8 bit recessivi).

**Fault confinement:** contatori TEC/REC, stati **error-active → error-passive
→ bus-off** e recupero da bus-off dopo 128 sequenze di 11 bit recessivi.

| Evento | Azione |
|---|---|
| Errore in trasmissione (bit/ACK/form) | TEC += 8 |
| Errore in ricezione (stuff/form/CRC) | REC += 1 |
| Trasmissione confermata (ACK) | TEC −= 1 |
| Ricezione valida | REC −= 1 |
| TEC > 127 o REC > 127 | → error-passive |
| TEC > 255 | → bus-off |

**Diagnostica:** `error_flag` (impulso), `error_passive`, `bus_off`,
`tec_value[7:0]`. Sul top il LED `led_error` è acceso su fault persistente
(error-passive o bus-off).

**Risincronizzazione:** correzione dell'errore di fase in **entrambe le
direzioni** (edge in TSEG1 → allunga; edge in TSEG2 → anticipa il bordo),
limitata a SJW → buona tolleranza tra oscillatori.

---

## 9. Target di sintesi e risultati

Lo stesso RTL è sintetizzato su due dispositivi (entrambi a configurazione
**interna non volatile**, programmazione `.pof` via JTAG):

| | **MAX V 5M1270ZT144C5N** | **MAX 10 10M08SAE144C8G** |
|---|---|---|
| Progetto | `quartus/` | `quartus_max10/` |
| Famiglia | CPLD (LUT-based), T144 | FPGA flash-based, E144 |
| Clock | 20 MHz | 50 MHz (wrapper, BRP=5) |
| Capacità | 1270 LE | 8000 LE |
| **Occupazione** | **~99 %** (~1256 LE) | **~16 %** (1256 LE) |
| Timing (setup slack) | +8.6 ns @ 20 MHz | +6.9 ns @ 50 MHz |
| Potenza stimata | — | ~184 mW |
| Toolchain | Quartus Lite ≤ 21.1 (25.x non ha MAX V) | Quartus Lite (incl. 25.1) |
| Config | flash interna, `.pof` | flash interna (CFM), `.pof` |
| Sicurezza firmware | interna + readback protection | interna + readback protection |

Note:
- Il MAX V è quasi pieno (~99 %): tenere l'effort del Fitter su Standard/High ed
  evitare di aggiungere logica. Il 5M1270 è il più grande MAX V in T144.
- Il MAX 10 lascia ampio margine (~16 %) per espansioni (PLL, USB, encoder Z,
  contatori 32 bit) mantenendo la filosofia monochip non volatile.
- Nessuno dei due supporta la **cifratura del bitstream (AES)**; la protezione è
  data dalla config interna + readback protection. Per AES servirebbe
  Cyclone 10 GX / Arria.

---

## 10. Pinout

### MAX V (5M1270ZT144) — `quartus/assign_pins.tcl`

| Segnale | Pin |
|---|---|
| clk | 18 (global clock) |
| rst_n | 16 |
| can_rxd / can_txd | 20 / 21 |
| node_addr[0..3] | 22, 23, 24, 27 |
| led_error | 28 |
| safe_ch1 / safe_ch2 | 29 / 30 |
| io[0..31] | 73,74,75,76,77,79,80,81,84,85,86,87,88,89,91,93,94,95,96,97,98,101,102,103,104,105,106,107,108,109,110,111 |
| enc_a[0..7] | 37,39,41,43,45,49,51,53 |
| enc_b[0..7] | 38,40,42,44,48,50,52,55 |

### MAX 10 (10M08SAE144) — `quartus_max10/assign_pins.tcl`

Pin diversi dal MAX V (famiglie/package diversi; JTAG 16/18/19/20 e config
126/129/136/138 sono dedicati). Assegnati per direzione e in ordine crescente.

| Segnale | Pin |
|---|---|
| clk | 28 (clock dedicato) |
| rst_n | 6 |
| can_rxd / can_txd | 7 / 59 |
| led_error | 57 |
| node_addr[0..3] | 15, 56, 61, 66 |
| safe_ch1 / safe_ch2 | 70 / 78 |
| io[0..31] | 8,10,11,12,13,14,17,21,22,55,60,62,88,92,93,96,97,98,99,100,101,102,111,112,114,118,119,120,121,122,124,134 |
| enc_a[0..7] | 79,81,85,87,90,105,123,131 |
| enc_b[0..7] | 80,84,86,89,91,113,127,132 |

> Sul **kit** di valutazione, `clk` va sul pin dell'oscillatore 50 MHz secondo
> il pin-out del kit; gli altri vanno mappati sugli header J8/J9/Arduino.

---

## 11. Simulazione

Testbench end-to-end: [sim/tb_can_ioexpander.vhd](../sim/tb_can_ioexpander.vhd)
— un nodo host (`can_controller`) e il DUT (`can_ioexpander_top`) su un bus CAN
in wired-AND, più un generatore di trama estesa per il test 2.0B.

**Copertura validata (GHDL, `run_exit=0`):**

1. CONFIG → OUTPUT → verifica uscite (0xBEEF)
2. STATUS automatico al variare di un ingresso
3. Iniezione bit/stuff error → error frame → recupero
4. Trama a identificatore esteso (2.0B passive): confermata ma ignorata
5. Sicurezza: apertura canale 1 e 2 → uscite a low + auto-ripristino
6. Encoder: 8 impulsi avanti → conteggio via ENC_DATA; ENC_RESET → azzeramento
7. ANALOG: letture ADC (con `ADC_PRESENT=true`) → verifica ch0/ch1 via CAN

**Esecuzione:**

```bash
bash sim/run_ghdl.sh            # Linux / macOS / Git Bash
```
```powershell
powershell -File sim\run_ghdl.ps1   # Windows
```

Richiede [GHDL](https://ghdl.github.io). A buon fine stampa
`*** TUTTI I TEST SUPERATI ***`.

---

## 12. Compilazione e programmazione

### Quartus

1. Apri il progetto: `quartus/can_ioexpander.qpf` (MAX V) o
   `quartus_max10/can_ioexpander_max10.qpf` (MAX 10).
2. Applica il pinout: *View → Tcl Console* → `source assign_pins.tcl`.
3. *Processing → Start Compilation* → genera `output_files/*.pof`.

> MAX V richiede una versione di Quartus con device support MAX V
> (≤ 21.1; le 25.x l'hanno rimosso). MAX 10 è supportato anche dalla 25.1.

### Programmazione (entrambi)

Configurazione **interna non volatile**: `Tools → Programmer` → hardware
**USB-Blaster** → modalità JTAG → carica il `.pof` → *Program/Configure* →
*Start*. Nessuna flash di configurazione esterna.

---

## 13. Note di progetto della scheda

- **Transceiver CAN 3.3 V** (es. SN65HVD230, MCP2562FD) su `can_txd`/`can_rxd`;
  terminazione **120 Ω** ai due estremi del bus.
- **Oscillatore**: 20 MHz (MAX V) o 50 MHz (MAX 10) sul pin di clock globale.
- **Alimentazioni**:
  - MAX V: core + VCCIO 3.3 V (poche rail).
  - MAX 10 single-supply (10M08**S**): regolatori interni → alimentazione
    semplificata, ma con i componenti esterni dei regolatori (cap/induttore) da
    datasheet. Consumo stimato ~184 mW → ampiamente entro il budget single-supply
    (verificare il `.pow.rpt`).
- **Ingressi non pilotati**: i pin `io` usati come ingresso e i due `safe_ch`
  richiedono **pull esterni** (pull-down sui safe → fail-safe).
- **MAX 10 e 3.3 V**: applicare **AN 447** (resistore serie/clamp) sugli I/O 3.3 V.
- **JTAG**: header 10-pin per la programmazione. Su MAX 10 i pin JTAG/config sono
  dedicati (non usabili come I/O).
- **node_addr[3:0]**: dip-switch a 4 vie con pull → indirizzo del nodo.

---

## 14. Strumenti host

### Driver ESP32 (TWAI) — `esp32/`

Componente ESP-IDF che comanda l'expander via la periferica CAN dell'ESP32
(TWAI), 500 kbit/s. API principali (`esp32/components/can_ioexpander/`):

| Funzione | Descrizione |
|---|---|
| `can_ioexpander_init(tx,rx)` | avvia TWAI a 500 kbit/s |
| `can_ioexpander_config_dir(node,mask)` | direzione pin |
| `can_ioexpander_set_outputs(node,val)` / `_masked(...)` | scrive le uscite |
| `can_ioexpander_request_status(node)` | richiede STATUS |
| `can_ioexpander_set_enc_period(node,ms)` | periodo TX encoder |
| `can_ioexpander_reset_encoders(node,mask)` | azzera contatori |
| `can_ioexpander_poll(node,&st,timeout)` | riceve STATUS/ENC_DATA → aggiorna `st` |

Serve un transceiver CAN 3.3 V esterno sui GPIO TX/RX. Build: `idf.py build`.
Dettagli in [../esp32/README.md](../esp32/README.md).

### GUI di test C# (WinForms) — `csharp_gui/`

Applicazione Windows che testa l'expander tramite convertitore **PEAK PCAN-USB**
(API PCAN-Basic): connessione, CONFIG, OUTPUT (32 toggle), STATUS in tempo reale,
encoder, log CAN. Richiede `PCANBasic.dll` (x64) e il driver PCAN-Basic.
Build: `dotnet build -c Release`. Dettagli in
[../csharp_gui/README.md](../csharp_gui/README.md).

---

## 15. Limitazioni note

- **CAN 2.0B**: solo *passive* (le trame estese sono tollerate/confermate, non
  trasmesse). Trasmissione di ID estesi non implementata.
- **Fault confinement** semplificato: niente overload frame, niente sospensione
  di trasmissione (8 bit) per i nodi error-passive, regole TEC/REC ridotte.
- **Encoder**: A/B senza canale di indice Z; contatori 16 bit (wrap a ±32767).
- **Sicurezza**: funzionale a doppio canale, senza diagnostica di discordanza né
  certificazione formale.
- **Cifratura firmware (AES)**: non disponibile su MAX V/MAX 10.
- **MAX V**: occupazione ~99 %, nessun margine per nuove funzioni.

---

## 16. Struttura del repository

```
rtl/                        Sorgenti VHDL (core + moduli + wrapper MAX 10)
sim/                        Testbench + script GHDL
doc/                        Documentazione (questo manuale, protocol.md, report)
quartus/                    Progetto Quartus MAX V (5M1270ZT144) + assign_pins.tcl
quartus_max10/              Progetto Quartus MAX 10 (10M08SAE144) + assign_pins.tcl
esp32/                      Driver ESP-IDF (TWAI) + esempio
csharp_gui/                 GUI di test Windows (PEAK PCAN-USB)
```

---

*Progetto cpld_can_ioexpander — documentazione della piattaforma. Validato in
simulazione (GHDL) e in sintesi (Quartus Prime Lite) sui target MAX V e MAX 10.*
