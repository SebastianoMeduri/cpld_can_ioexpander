/*
 * can_ioexpander.c  --  Driver ESP-IDF (TWAI) per l'I/O expander CAN su CPLD.
 * Vedi can_ioexpander.h e doc/protocol.md.
 */
#include "can_ioexpander.h"
#include "driver/twai.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

/* Codici FUNC del protocollo (bit 10..8 dell'ID) */
#define FUNC_ENCPER  0x0
#define FUNC_OUTPUT  0x1
#define FUNC_CONFIG  0x2
#define FUNC_REQUEST 0x3
#define FUNC_STATUS  0x4
#define FUNC_ENCRST  0x5
#define FUNC_ENC     0x6

/* ID = FUNC(3) & NODE(4) & SUB(4) */
#define IOEXP_ID(func, node, sub) \
    ((((uint32_t)(func) & 0x7) << 8) | (((uint32_t)(node) & 0xF) << 4) | ((uint32_t)(sub) & 0xF))

#define TX_TIMEOUT_MS 20

/* Impacchetta una word a 32 bit (pin i = bit i) in 4 byte big-endian
 * secondo la convenzione: byte0 = pin31..24 ... byte3 = pin7..0. */
static inline void pack_pinword(uint32_t w, uint8_t *b)
{
    b[0] = (uint8_t)(w >> 24);
    b[1] = (uint8_t)(w >> 16);
    b[2] = (uint8_t)(w >> 8);
    b[3] = (uint8_t)(w);
}

static esp_err_t send_frame(uint32_t id, const uint8_t *data, uint8_t dlc)
{
    twai_message_t m = {0};
    m.identifier = id;
    m.extd = 0;                 /* frame standard 11 bit */
    m.rtr  = 0;
    m.data_length_code = dlc;
    for (uint8_t i = 0; i < dlc && i < 8; i++) {
        m.data[i] = data[i];
    }
    return twai_transmit(&m, pdMS_TO_TICKS(TX_TIMEOUT_MS));
}

esp_err_t can_ioexpander_init(int tx_gpio, int rx_gpio)
{
    twai_general_config_t g =
        TWAI_GENERAL_CONFIG_DEFAULT((gpio_num_t)tx_gpio, (gpio_num_t)rx_gpio, TWAI_MODE_NORMAL);
    twai_timing_config_t t = TWAI_TIMING_CONFIG_500KBITS();   /* stesso bitrate dell'expander */
    twai_filter_config_t f = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    esp_err_t e = twai_driver_install(&g, &t, &f);
    if (e != ESP_OK) {
        return e;
    }
    return twai_start();
}

void can_ioexpander_deinit(void)
{
    twai_stop();
    twai_driver_uninstall();
}

esp_err_t can_ioexpander_config_dir(uint8_t node, uint32_t dir_mask)
{
    uint8_t d[4];
    pack_pinword(dir_mask, d);
    return send_frame(IOEXP_ID(FUNC_CONFIG, node, 0), d, 4);
}

esp_err_t can_ioexpander_set_outputs(uint8_t node, uint32_t values)
{
    uint8_t d[4];
    pack_pinword(values, d);
    return send_frame(IOEXP_ID(FUNC_OUTPUT, node, 0), d, 4);
}

esp_err_t can_ioexpander_set_outputs_masked(uint8_t node, uint32_t values, uint32_t mask)
{
    uint8_t d[8];
    pack_pinword(values, &d[0]);   /* byte 0..3 = valori */
    pack_pinword(mask,   &d[4]);   /* byte 4..7 = maschera di scrittura */
    return send_frame(IOEXP_ID(FUNC_OUTPUT, node, 0), d, 8);
}

esp_err_t can_ioexpander_request_status(uint8_t node)
{
    return send_frame(IOEXP_ID(FUNC_REQUEST, node, 0), NULL, 0);
}

esp_err_t can_ioexpander_set_enc_period(uint8_t node, uint16_t period_ms)
{
    /* periodo in data[63:48] = byte0 (MSB) e byte1 (LSB) */
    uint8_t d[2] = { (uint8_t)(period_ms >> 8), (uint8_t)(period_ms) };
    return send_frame(IOEXP_ID(FUNC_ENCPER, node, 0), d, 2);
}

esp_err_t can_ioexpander_reset_encoders(uint8_t node, uint8_t enc_mask)
{
    /* la maschera di reset e' letta dall'expander in data[7:0] = byte 7 -> DLC 8 */
    uint8_t d[8] = {0, 0, 0, 0, 0, 0, 0, enc_mask};
    return send_frame(IOEXP_ID(FUNC_ENCRST, node, 0), d, 8);
}

esp_err_t can_ioexpander_poll(uint8_t node, can_ioexpander_state_t *st, uint32_t timeout_ms)
{
    twai_message_t m;
    esp_err_t e = twai_receive(&m, pdMS_TO_TICKS(timeout_ms));
    if (e != ESP_OK) {
        return e;                          /* tipicamente ESP_ERR_TIMEOUT */
    }
    if (m.extd) {
        return ESP_ERR_NOT_FOUND;          /* ignora trame a ID esteso */
    }

    uint8_t nd   = (uint8_t)((m.identifier >> 4) & 0xF);
    uint8_t func = (uint8_t)((m.identifier >> 8) & 0x7);
    if (nd != node) {
        return ESP_ERR_NOT_FOUND;
    }

    if (func == FUNC_STATUS && m.data_length_code >= 4) {
        st->inputs = ((uint32_t)m.data[0] << 24) | ((uint32_t)m.data[1] << 16) |
                     ((uint32_t)m.data[2] << 8)  |  (uint32_t)m.data[3];
        st->status_valid = true;
        return ESP_OK;
    }

    if (func == FUNC_ENC && m.data_length_code >= 8) {
        uint8_t sub  = (uint8_t)(m.identifier & 0xF);   /* 0 -> enc0..3, 1 -> enc4..7 */
        int     base = (sub == 1) ? 4 : 0;
        for (int i = 0; i < 4; i++) {
            st->enc[base + i] =
                (int16_t)(((uint16_t)m.data[2 * i] << 8) | m.data[2 * i + 1]);
        }
        st->enc_valid = true;
        return ESP_OK;
    }

    return ESP_ERR_NOT_FOUND;
}
