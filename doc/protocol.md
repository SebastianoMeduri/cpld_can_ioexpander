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
ID[3:0]  = 0000   (riservato)
```

| FUNC  | Nome    | Direzione   | Descrizione                                  |
|-------|---------|-------------|----------------------------------------------|
| `010` | CONFIG  | host -> exp | imposta la direzione dei pin                 |
| `001` | OUTPUT  | host -> exp | imposta i valori delle uscite                |
| `011` | REQUEST | host -> exp | richiede l'invio immediato dello stato       |
| `100` | STATUS  | exp -> host | stato corrente dei pin                       |

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

### CONFIG (FUNC=010, DLC=4)
`data[63:32]` = maschera di direzione. Bit a `1` = pin in **uscita**,
bit a `0` = pin in **ingresso** (default al reset: tutti ingressi, alta impedenza).

### OUTPUT (FUNC=001, DLC=4 oppure 8)
`data[63:32]` = valori da applicare ai pin configurati come uscita.
Con **DLC=8**, `data[31:0]` e' una maschera di scrittura: vengono aggiornati
solo i bit a `1` (read-modify-write). Con **DLC=4** si aggiornano tutte le uscite.

### REQUEST (FUNC=011, DLC=0)
Forza il nodo a trasmettere subito una trama STATUS.

### STATUS (FUNC=100, DLC=4)
Inviata dall'expander:
* su ricezione di un REQUEST;
* automaticamente quando cambia un pin configurato come ingresso.

`data[63:32]` = stato dei pin: per le uscite il valore pilotato, per gli
ingressi il valore letto.

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
