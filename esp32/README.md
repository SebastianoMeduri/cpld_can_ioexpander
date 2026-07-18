# Driver ESP32 (TWAI) per l'I/O expander CAN

Componente ESP-IDF + esempio per comandare l'espansore via la periferica CAN
dell'ESP32 (**TWAI**). Parla il protocollo descritto in
[../doc/protocol.md](../doc/protocol.md): frame standard 2.0A, 500 kbit/s.

## Struttura

```
esp32/
  CMakeLists.txt                      progetto ESP-IDF
  main/
    main.c                            esempio d'uso
    CMakeLists.txt
  components/can_ioexpander/
    include/can_ioexpander.h          API del driver
    can_ioexpander.c                  implementazione (TWAI)
    CMakeLists.txt
```

## Collegamento hardware

L'ESP32 **non** ha un transceiver CAN integrato: serve un transceiver 3.3 V
(es. **SN65HVD230**, MCP2562FD) sui GPIO TX/RX.

```
ESP32 GPIO_TX ──> TXD ┐                        ┌ RXD <── CPLD can_rxd
ESP32 GPIO_RX <── RXD ┤  transceiver   CAN_H ──┼──────── CAN_H
                      │  (3.3 V)       CAN_L ──┼──────── CAN_L
                      └ transceiver ESP32      └ transceiver expander
```

* Stesso **bus** per ESP32 ed expander, **500 kbit/s** su entrambi.
* **Terminazione 120 Ω** ai due estremi fisici del bus.
* `NODE` nel firmware = `node_addr` strappato sul CPLD (default 1).

## Build

```bash
cd esp32
idf.py set-target esp32
idf.py build flash monitor
```

(Impostare i GPIO in [main/main.c](main/main.c): default TX=21, RX=22.)

## API (can_ioexpander.h)

| Funzione | Descrizione |
|---|---|
| `can_ioexpander_init(tx,rx)` | installa/avvia TWAI a 500 kbit/s |
| `can_ioexpander_config_dir(node,mask)` | direzione pin (bit i=1 → uscita) |
| `can_ioexpander_set_outputs(node,val)` | scrive tutte le uscite |
| `can_ioexpander_set_outputs_masked(node,val,mask)` | scrive solo i pin con mask=1 |
| `can_ioexpander_request_status(node)` | richiede una trama STATUS |
| `can_ioexpander_set_enc_period(node,ms)` | periodo TX encoder (0=off) |
| `can_ioexpander_reset_encoders(node,mask)` | azzera contatori (bit i=encoder i) |
| `can_ioexpander_poll(node,&st,timeout)` | riceve STATUS/ENC_DATA → aggiorna `st` |

`st.inputs` è la word a 32 bit dei pin (bit i = pin i); `st.enc[0..7]` sono i
conteggi encoder (`int16` con segno).

## Esempio minimo

```c
can_ioexpander_init(21, 22);
can_ioexpander_config_dir(1, 0xFFFF0000);   // pin31..16 uscite
can_ioexpander_set_outputs(1, 0x00050000);  // pin16 e pin18 alti
can_ioexpander_set_enc_period(1, 20);       // encoder ogni 20 ms

can_ioexpander_state_t st = {0};
while (1) {
    if (can_ioexpander_poll(1, &st, 100) == ESP_OK) {
        // usa st.inputs, st.enc[...]
    }
}
```

## Note

* Il driver ignora le trame a identificatore esteso (29 bit); l'expander le
  tollera comunque sul bus (2.0B passive).
* Verifica che il sample point del preset `TWAI_TIMING_CONFIG_500KBITS()`
  (~75–80 %) sia coerente con l'expander (80 %): lo è per i preset standard.
