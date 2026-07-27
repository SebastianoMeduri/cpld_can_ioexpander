/*
 * can_ioexpander.h  --  Driver ESP-IDF (TWAI) per l'I/O expander CAN su CPLD.
 *
 * Parla il protocollo dell'espansore (vedi doc/protocol.md):
 *   ID a 11 bit = FUNC(3) & NODE(4) & SUB(4)
 *   500 kbit/s, frame standard (2.0A).
 *
 * Uso tipico:
 *   can_ioexpander_init(GPIO_TX, GPIO_RX);
 *   can_ioexpander_config_dir(1, 0xFFFF0000);      // pin31..16 uscite
 *   can_ioexpander_set_outputs(1, 0x00010000);     // pin16 alto
 *   can_ioexpander_set_enc_period(1, 20);          // encoder ogni 20 ms
 *   can_ioexpander_state_t st = {0};
 *   while (1) can_ioexpander_poll(1, &st, 100);    // aggiorna st.inputs / st.enc[]
 *
 * NB lato hardware: l'ESP32 non ha transceiver CAN integrato -> serve un
 * transceiver 3.3 V (es. SN65HVD230) sui GPIO TX/RX, stesso bus dell'expander,
 * terminazione 120 Ohm ai due estremi, stesso bitrate (500 kbit/s).
 */
#pragma once

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Stato aggregato aggiornato da can_ioexpander_poll(). */
typedef struct {
    uint32_t inputs;        /* stato dei 32 pin (bit i = pin i), da STATUS   */
    bool     status_valid;  /* true dopo la prima trama STATUS               */
    int16_t  enc[8];        /* conteggi degli 8 encoder, da ENC_DATA         */
    bool     enc_valid;     /* true dopo la prima trama ENC_DATA             */
    uint16_t adc[8];        /* letture ADC 12 bit (solo MAX 10), da ANALOG   */
    bool     adc_valid;     /* true dopo la prima trama ANALOG di letture    */
    uint8_t  adc_over;      /* bitmap confronto soglie: bit i = adc[i]>=thr[i]*/
    bool     adc_over_valid;/* true dopo la prima trama ANALOG bitmap (SUB=2)*/
} can_ioexpander_state_t;

/* Installa e avvia il driver TWAI a 500 kbit/s. */
esp_err_t can_ioexpander_init(int tx_gpio, int rx_gpio);

/* Ferma e disinstalla il driver TWAI. */
void can_ioexpander_deinit(void);

/* CONFIG: direzione dei pin, bit i = pin i (1 = uscita, 0 = ingresso). */
esp_err_t can_ioexpander_config_dir(uint8_t node, uint32_t dir_mask);

/* OUTPUT: scrive tutti i valori delle uscite (bit i = pin i). */
esp_err_t can_ioexpander_set_outputs(uint8_t node, uint32_t values);

/* OUTPUT con maschera: aggiorna solo i pin con mask=1 (read-modify-write). */
esp_err_t can_ioexpander_set_outputs_masked(uint8_t node, uint32_t values, uint32_t mask);

/* REQUEST: chiede l'invio immediato di una trama STATUS. */
esp_err_t can_ioexpander_request_status(uint8_t node);

/* ENC_PERIOD: periodo di trasmissione encoder in ms (0 = disabilita). */
esp_err_t can_ioexpander_set_enc_period(uint8_t node, uint16_t period_ms);

/* ENC_RESET: azzera i contatori selezionati (bit i = encoder i). */
esp_err_t can_ioexpander_reset_encoders(uint8_t node, uint8_t enc_mask);

/*
 * Soglie ADC (solo MAX 10). Imposta gli 8 registri di soglia (12 bit utili)
 * inviando due trame CONFIG (SUB=1 ch0..3, SUB=2 ch4..7). L'expander confronta
 * di continuo adc[i] >= thr[i] e riporta il bitmap con ANALOG SUB=2 (vedi
 * st.adc_over aggiornato da can_ioexpander_poll). Al reset le soglie sono a
 * fondo scala (0xFFF), cioe' nessun canale in allarme.
 */
esp_err_t can_ioexpander_set_adc_thresholds(uint8_t node, const uint16_t thr[8]);

/*
 * Riceve una trama (attesa max timeout_ms) e, se proviene dal nodo indicato,
 * aggiorna *st. Ritorna:
 *   ESP_OK             -> trama STATUS / ENC_DATA / ANALOG del nodo elaborata
 *   ESP_ERR_TIMEOUT    -> nessuna trama entro il timeout
 *   ESP_ERR_NOT_FOUND  -> trama ricevuta ma non pertinente (altro nodo/funzione)
 */
esp_err_t can_ioexpander_poll(uint8_t node, can_ioexpander_state_t *st, uint32_t timeout_ms);

#ifdef __cplusplus
}
#endif
