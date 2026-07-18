/*
 * Esempio d'uso del driver can_ioexpander su ESP32 (TWAI).
 *
 * Cablaggio: GPIO_TX/GPIO_RX -> transceiver CAN 3.3 V (es. SN65HVD230) ->
 * stesso bus dell'expander, terminazione 120 Ohm ai due estremi, 500 kbit/s.
 *
 * Scenario:
 *   - configura pin 31..16 come uscite, 15..0 come ingressi
 *   - fa lampeggiare un pattern sulle uscite
 *   - abilita la trasmissione periodica degli encoder (50 ms)
 *   - stampa ingressi ed encoder man mano che arrivano
 */
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "can_ioexpander.h"

#define GPIO_CAN_TX   21     /* -> TXD del transceiver */
#define GPIO_CAN_RX   22     /* <- RXD del transceiver */
#define NODE          1      /* deve combaciare con node_addr del CPLD */

static const char *TAG = "ioexp";

void app_main(void)
{
    ESP_ERROR_CHECK(can_ioexpander_init(GPIO_CAN_TX, GPIO_CAN_RX));
    ESP_LOGI(TAG, "TWAI avviato a 500 kbit/s (nodo %d)", NODE);

    /* pin 31..16 = uscite, pin 15..0 = ingressi */
    ESP_ERROR_CHECK(can_ioexpander_config_dir(NODE, 0xFFFF0000));

    /* trasmissione periodica encoder ogni 50 ms; azzera i contatori */
    can_ioexpander_set_enc_period(NODE, 50);
    can_ioexpander_reset_encoders(NODE, 0xFF);

    can_ioexpander_state_t st = {0};
    uint16_t pattern = 0x0001;
    TickType_t last_out = xTaskGetTickCount();

    while (1) {
        /* aggiorna lo stato ricevendo STATUS / ENC_DATA (non blocca oltre 50 ms) */
        esp_err_t e = can_ioexpander_poll(NODE, &st, 50);
        if (e == ESP_OK && st.status_valid) {
            ESP_LOGI(TAG, "inputs=0x%08lx  enc0=%d enc1=%d enc2=%d enc3=%d",
                     (unsigned long)st.inputs, st.enc[0], st.enc[1], st.enc[2], st.enc[3]);
        }

        /* ogni 500 ms sposta il pattern sulle uscite (pin 31..16) */
        if ((xTaskGetTickCount() - last_out) >= pdMS_TO_TICKS(500)) {
            last_out = xTaskGetTickCount();
            can_ioexpander_set_outputs(NODE, (uint32_t)pattern << 16);
            pattern = (uint16_t)((pattern << 1) | (pattern >> 15));  /* rotazione */
        }
    }
}
