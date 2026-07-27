# Protocollo CAN dell'I/O expander

## Parametri del bus

| Parametro        | Valore di default                     |
|------------------|---------------------------------------|
| Standard         | CAN 2.0A (11 bit) + 2.0B passive (tollera trame estese 29 bit) |
| Bitrate          | 500 kbit/s                            |
| Clock di sistema | 20 MHz                                |
| Bit timing       | BRP=2, TSEG1=15, TSEG2=4, SJW=3 (20 Tq/bit, sample point 80%) |

Bitrate diversi si ottengono cambiando i `generic` del top level
(`BRP`, `TSEG1`, `TSEG2`, `SJW`). Vale la relazione:

```
Tq       = BRP / f_clk
bit_time = (1 + TSEG1 + TSEG2) * Tq = 1 / bitrate
```

## Formato dell'identificatore (11 bit)

```
ID[10:8] = FUNC   (funzione)
ID[7:4]  = NODE   (indirizzo del nodo, ingresso node_addr)
ID[3:0]  = SUB    (0000; per ENC_DATA = indice blocco)
```

| FUNC  | Nome       | Direzione   | Descrizione                                       |
|-------|------------|-------------|---------------------------------------------------|
| `000` | ENC_PERIOD | host -> exp | periodo TX encoder in ms: `data[63:48]` (0 = off) |
| `001` | OUTPUT     | host -> exp | imposta i valori delle uscite                     |
| `010` | CONFIG     | host -> exp | SUB=0 direzione pin; SUB=1/2 soglie ADC (MAX 10)  |
| `011` | REQUEST    | host -> exp | richiede l'invio immediato dello STATUS           |
| `100` | STATUS     | exp -> host | stato corrente dei pin                            |
| `101` | ENC_RESET  | host -> exp | `data[7:0]`: bit i azzera il contatore encoder i  |
| `110` | ENC_DATA   | exp -> host | conteggi encoder (SUB=0 → enc0..3, SUB=1 → enc4..7) |
| `111` | ANALOG     | exp -> host | letture ADC — solo MAX 10 (SUB=0 → ch0..3, SUB=1 → ch4..7, SUB=2 → bitmap confronto soglie) |

I codici FUNC dei comandi host->exp sono piu' bassi di ENC_DATA/ANALOG cosi' che
l'host vinca sempre l'arbitraggio anche durante la trasmissione periodica.

## Mappatura dei pin nel payload

Il campo dati inizia con 4 byte (32 bit) che rappresentano i 32 pin:

```
pin i  <->  bit (32 + i) della trama a 64 bit
byte0 (data[63:56]) = pin 31..24
byte1 (data[55:48]) = pin 23..16
byte2 (data[47:40]) = pin 15..8
byte3 (data[39:32]) = pin 7..0
```

## Dettaglio dei messaggi

### CONFIG (FUNC=010)
Il campo **SUB** (`ID[3:0]`) seleziona il sotto-comando:

* **SUB=0** (DLC=4) — *direzione pin*: `data[63:32]` = maschera di direzione.
  Bit a `1` = pin in **uscita**, bit a `0` = pin in **ingresso**
  (default al reset: tutti ingressi, alta impedenza).
* **SUB=1 / SUB=2** (DLC=8) — *soglie ADC* (solo MAX 10): impostano i registri di
  soglia dei canali analogici (vedi sezione «Soglie e confronto ADC»).

### OUTPUT (FUNC=001, DLC=4 oppure 8)
`data[63:32]` = valori da applicare ai pin configurati come uscita.
Con **DLC=8**, `data[31:0]` e' una maschera di scrittura: vengono aggiornati
solo i bit a `1` (read-modify-write). Con **DLC=4** si aggiornano tutte le uscite.

### REQUEST (FUNC=011, DLC=0)
Forza il nodo a trasmettere subito una trama STATUS.

### STATUS (FUNC=100, DLC=4)
Inviata dall'expander:
* su ricezione di un REQUEST;
* automaticamente quando cambia un pin configurato come ingresso;
* automaticamente ad ogni transizione della funzione di sicurezza.

`data[63:32]` = stato dei pin: per le uscite il valore **effettivo** (forzato a
0 se la sicurezza e' intervenuta), per gli ingressi il valore letto.

## Funzione di sicurezza (doppio canale fail-safe)

Due ingressi di consenso attivi-alti, `safe_ch1` e `safe_ch2`. Le uscite sono
abilitate solo se **entrambi** sono alti. Se uno qualsiasi va basso (E-stop,
filo interrotto, mancanza segnale) tutte le uscite vengono **forzate a livello
basso** (override combinatorio, indipendente dai comandi CAN). Il ripristino e'
**automatico** al ritorno del consenso. Prevedere pull-down esterni sui due
ingressi cosi' che la perdita di segnale porti allo stato sicuro.

## Esempi (NODE = 0001)

Codifica degli ID con NODE=`0001`:

| Messaggio | Binario        | Hex   |
|-----------|----------------|-------|
| CONFIG    | `01000010000`  | 0x210 |
| OUTPUT    | `00100010000`  | 0x110 |
| REQUEST   | `01100010000`  | 0x310 |
| STATUS    | `10000010000`  | 0x410 |

```
# Nodo 1: pin 31..16 uscite, pin 15..0 ingressi
ID=0x210  DLC=4  DATA=FF FF 00 00

# Nodo 1: porta le uscite alte (pin 31..16) a 0xBEEF
ID=0x110  DLC=4  DATA=BE EF 00 00

# Nodo 1: richiesta stato -> il nodo risponde con ID=0x410
ID=0x310  DLC=0
```

## Encoder incrementali (8 canali)

Otto encoder in quadratura A/B (`enc_a[7:0]`, `enc_b[7:0]`), decodifica **x4**,
contatori a **16 bit con segno**. I conteggi sono trasmessi **periodicamente** su
CAN con due trame ENC_DATA (DLC=8):

* **SUB=0** (`ID[3:0]=0000`): encoder 0..3;
* **SUB=1** (`ID[3:0]=0001`): encoder 4..7.

In ogni trama i 4 conteggi sono `int16` in ordine, con l'encoder di indice piu'
basso nei byte piu' significativi:
`data[63:48]=enc(k)`, `[47:32]=enc(k+1)`, `[31:16]=enc(k+2)`, `[15:0]=enc(k+3)`.

* **ENC_PERIOD** (FUNC=000): imposta il periodo di trasmissione in ms
  (`data[63:48]`); 0 disabilita la trasmissione periodica.
* **ENC_RESET** (FUNC=101): `data[7:0]` bitmask, il bit i azzera il contatore
  dell'encoder i.

## Ingressi analogici (solo MAX 10)

Sul target MAX 10 (10M08SA, ADC 12 bit integrato) l'expander legge **8 canali
analogici** e li trasmette con il messaggio **ANALOG** (FUNC=111, DLC=8), con la
stessa cadenza periodica degli encoder:

* **SUB=0** (`ID[3:0]=0000`): canali 0..3;
* **SUB=1** (`ID[3:0]=0001`): canali 4..7.

Ogni trama contiene 4 valori `uint16` (12 bit utili, giustificati a destra),
canale di indice piu' basso nei byte piu' significativi:
`data[63:48]=ch(k)`, `[47:32]=ch(k+1)`, `[31:16]=ch(k+2)`, `[15:0]=ch(k+3)`.

Il messaggio ANALOG è assente sul MAX V (CPLD senza ADC). Vedere il manuale per
l'abilitazione dell'ADC sul MAX 10.

## Soglie e confronto ADC (solo MAX 10)

Ogni canale analogico ha un **registro di soglia a 12 bit** configurabile via CAN.
L'expander confronta di continuo la lettura con la soglia e mantiene un **bitmap a
8 bit** (`over`): `over[i] = 1` se `adc[i] >= soglia[i]`.

### Impostazione delle soglie — CONFIG SUB=1/2 (DLC=8)

Le soglie si scrivono con il messaggio CONFIG usando il campo SUB, 4 canali per
trama con lo stesso ordinamento delle letture (canale più basso nei byte alti):

* **SUB=1** (`ID[3:0]=0001`): soglie ch0..3 —
  `data[63:48]=thr(ch0)`, `[47:32]=thr(ch1)`, `[31:16]=thr(ch2)`, `[15:0]=thr(ch3)`;
* **SUB=2** (`ID[3:0]=0010`): soglie ch4..7 (stesso schema, ch4..7).

Si usano i 12 bit meno significativi di ogni `uint16`. Al reset le soglie valgono
**0xFFF** (fondo scala) → nessun canale in allarme finché non vengono configurate.

### Notifica del confronto — ANALOG SUB=2 (DLC=1)

L'expander invia il bitmap `over` con il messaggio ANALOG `SUB=2`:
`data[63:56]` = `over[7:0]` (bit `i` = canale `i` sopra soglia). La trama è inviata:

* **in coda** alla sequenza periodica delle letture ANALOG;
* **immediatamente** ad ogni variazione del bitmap (funziona da comparatore/allarme
  analogico, come lo STATUS per gli ingressi digitali).

Esempio (NODE=0001): scrittura soglie ch0..3 → `ID=0x211 DLC=8`; bitmap di
confronto → `ID=0x712 DLC=1 DATA=xx…` con `data[63:56]` = bitmap.

## Gestione errori e fault confinement

Il core implementa il livello MAC di CAN 2.0A con:

* bit stuffing / de-stuffing;
* monitoraggio del bus, perdita di arbitraggio, **bit error**;
* rilevazione di **stuff error**, **form error** (delimitatori e EOF),
  **ACK error** (trasmettitore) e **CRC error** (ricevitore);
* **error frame** conformi: flag *attivo* (6 bit dominanti) se error-active,
  flag *passivo* (6 bit recessivi) se error-passive, seguito da error
  delimiter (8 bit recessivi);
* **fault confinement** (ISO 11898-1, semplificato): contatori TEC/REC, stati
  **error-active / error-passive / bus-off** e recupero da bus-off dopo 128
  sequenze di 11 bit recessivi;
* ACK e ritrasmissione automatica in assenza di conferma;
* **CAN 2.0B passive**: le trame a identificatore esteso (29 bit) vengono
  seguite e confermate con ACK ma non consegnate all'applicazione — così un
  nodo 11-bit non disturba una rete mista 11/29 bit;
* **risincronizzazione** con correzione dell'errore di fase in entrambe le
  direzioni (TSEG1/TSEG2, limitata a SJW) per la tolleranza di clock.

Segnali di diagnostica esposti dal controller: `error_flag` (impulso),
`error_passive`, `bus_off`, `tec_value[7:0]`. Sul top level il LED
`led_error` si accende su fault persistente (error-passive o bus-off).

### Regole TEC/REC (semplificate)

| Evento | Azione |
|--------|--------|
| Errore in trasmissione (bit/ACK/form) | TEC += 8 |
| Errore in ricezione (stuff/form/CRC)  | REC += 1 |
| Trasmissione confermata (ACK)         | TEC -= 1 |
| Ricezione valida                      | REC -= 1 |
| TEC > 127 oppure REC > 127            | → error-passive |
| TEC > 255                             | → bus-off |

### Limitazioni residue

**Non** implementati (semplificazioni rispetto a ISO 11898-1): **trasmissione**
di trame a identificatore esteso 29 bit (la ricezione 2.0B passive c'e'),
overload frame, sospensione di trasmissione (8 bit) per i nodi error-passive,
regole complete di eccezione sugli incrementi TEC/REC, filtri hardware di
accettazione multipli.
