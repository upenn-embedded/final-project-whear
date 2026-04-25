/* YRM100 UHF RFID reader driver.
 *
 * This is our portable driver for the YRM100X RFID reader module. The
 * module speaks a simple packet protocol over a 3.3 V UART:
 *
 *   [HEADER=0xBB][TYPE][CMD][PARAM_LEN (2 bytes, big-endian)]
 *                               [params...][CHECKSUM][END=0x7E]
 *
 * We can talk to it from any MCU — the driver itself has no STM32-specific
 * code. The user of the driver just fills out a struct of UART callbacks
 * (init/send/recv/available) and passes it in, so this same code would
 * work on Arduino, ESP32, anything. That separation-of-concerns idea is
 * basically the "hardware abstraction layer" idea from lecture. */

#ifndef YRM100_H
#define YRM100_H

#include <stdint.h>
#include <stddef.h>

/* ── Frame delimiters ───────────────────────────────────────────────
 * Every frame going either direction is bookended by these magic bytes.
 * They make it easy to re-sync the parser if we ever drop a byte — just
 * keep reading until we see 0xBB, which is the "start of frame" marker. */
#define YRM100_HEADER 0xBB
#define YRM100_END    0x7E

/* ── Frame types ──────────────────────────────────────────────────── */
/* Second byte of every frame indicates who's talking to whom and why. */
#define YRM100_TYPE_CMD      0x00   /* host  -> module  */
#define YRM100_TYPE_RESPONSE 0x01   /* module -> host   */
#define YRM100_TYPE_NOTICE   0x02   /* module -> host (inventory notification) */

/* ── Command codes ────────────────────────────────────────────────── */
#define YRM100_CMD_GET_INFO          0x03
#define YRM100_CMD_SET_BAUD          0x11
#define YRM100_CMD_SET_REGION        0x07
#define YRM100_CMD_GET_REGION        0x08
#define YRM100_CMD_SET_CHANNEL       0xAB
#define YRM100_CMD_GET_CHANNEL       0xAA
#define YRM100_CMD_SET_FREQ_HOP      0xAD
#define YRM100_CMD_INSERT_CHANNEL    0xA9
#define YRM100_CMD_GET_TX_POWER      0xB7
#define YRM100_CMD_SET_TX_POWER      0xB6
#define YRM100_CMD_SET_CW            0xB0
#define YRM100_CMD_GET_MODEM_PARAMS  0xF1
#define YRM100_CMD_SET_MODEM_PARAMS  0xF0
#define YRM100_CMD_SCAN_JAMMER       0xF2
#define YRM100_CMD_SCAN_RSSI         0xF3
#define YRM100_CMD_SET_SELECT        0x0C
#define YRM100_CMD_GET_SELECT        0x0B
#define YRM100_CMD_SET_SELECT_MODE   0x12
#define YRM100_CMD_GET_QUERY         0x0D
#define YRM100_CMD_SET_QUERY         0x0E
#define YRM100_CMD_SINGLE_INVENTORY  0x22
#define YRM100_CMD_MULTI_INVENTORY   0x27
#define YRM100_CMD_STOP_INVENTORY    0x28
#define YRM100_CMD_READ              0x39
#define YRM100_CMD_WRITE             0x49
#define YRM100_CMD_LOCK              0x82
#define YRM100_CMD_KILL              0x65
#define YRM100_CMD_SLEEP             0x17
#define YRM100_CMD_SET_IDLE_TIME     0x1D
#define YRM100_CMD_IDLE_MODE         0x04
#define YRM100_CMD_ERROR             0xFF

/* ── Info sub-types (for GET_INFO) ────────────────────────────────── */
#define YRM100_INFO_HW_VERSION   0x00
#define YRM100_INFO_SW_VERSION   0x01
#define YRM100_INFO_MANUFACTURER 0x02

/* ── Memory banks ─────────────────────────────────────────────────── */
#define YRM100_MEMBANK_RFU  0x00
#define YRM100_MEMBANK_EPC  0x01
#define YRM100_MEMBANK_TID  0x02
#define YRM100_MEMBANK_USER 0x03

/* ── Regions ──────────────────────────────────────────────────────── */
#define YRM100_REGION_CHINA2 0x01   /* 920-925 MHz  */
#define YRM100_REGION_US     0x02   /* 902.25-927.75 MHz */
#define YRM100_REGION_EUROPE 0x03   /* 865-868 MHz  */
#define YRM100_REGION_CHINA1 0x04   /* 840-845 MHz  */
#define YRM100_REGION_KOREA  0x06   /* 917-923 MHz  */

/* ── Baud rate parameters ─────────────────────────────────────────── */
#define YRM100_BAUD_9600   0x00C0   /* param for set baud cmd */
#define YRM100_BAUD_19200  0x0060
#define YRM100_BAUD_38400  0x0030
#define YRM100_BAUD_57600  0x0020
#define YRM100_BAUD_115200 0x0010

/* ── TX power presets (value = power_dBm * 100) ───────────────────── */
#define YRM100_POWER_1850  0x04E2   /* 18.5 dBm */
#define YRM100_POWER_2000  0x0578   /* 20   dBm */
#define YRM100_POWER_2150  0x060E   /* 21.5 dBm */
#define YRM100_POWER_2300  0x06A4   /* 23   dBm */
#define YRM100_POWER_2450  0x073A   /* 24.5 dBm */
#define YRM100_POWER_2600  0x07D0   /* 26   dBm (max, default) */

/* ── Select mode ──────────────────────────────────────────────────── */
#define YRM100_SEL_MODE_ALL      0x00   /* select before all operations     */
#define YRM100_SEL_MODE_NONE     0x01   /* never send select                */
#define YRM100_SEL_MODE_NON_INV  0x02   /* select before all except inventory */

/* ── Error codes ──────────────────────────────────────────────────── */
#define YRM100_ERR_CMD_FAIL          0x09
#define YRM100_ERR_WRITE_NO_TAG      0x10
#define YRM100_ERR_LOCK_NO_TAG       0x13
#define YRM100_ERR_INVENTORY_NO_TAG  0x15
#define YRM100_ERR_ACCESS_PASSWORD   0x16
#define YRM100_ERR_READ_OVERRUN      0xA3
#define YRM100_ERR_OTHER             0xB0
#define YRM100_ERR_MEM_OVERRUN       0xB3
#define YRM100_ERR_MEM_LOCKED        0xB4
#define YRM100_ERR_INSUF_POWER       0xBB
#define YRM100_ERR_LOCK_OTHER        0xC0
#define YRM100_ERR_LOCK_OVERRUN      0xC3
#define YRM100_ERR_LOCK_LOCKED       0xC4
#define YRM100_ERR_LOCK_INSUF_POWER  0xCB

/* ── Buffer sizes ─────────────────────────────────────────────────── */
#define YRM100_MAX_FRAME_LEN  256
#define YRM100_MAX_EPC_LEN    62   /* max PC+EPC bytes */

/* ── Return status ──────────────────────────────────────────────────
 * Every driver function returns one of these so the caller can tell
 * what went wrong. We pretty much only ever look at OK vs. TIMEOUT in
 * main.c, but the more granular codes are here for debugging. */
typedef enum {
    YRM100_OK = 0,
    YRM100_ERR_TIMEOUT,
    YRM100_ERR_CHECKSUM,
    YRM100_ERR_BAD_FRAME,
    YRM100_ERR_MODULE,   /* module returned an error response */
} yrm100_status_t;

/* ── Tag inventory result ───────────────────────────────────────────
 * What one RFID read looks like after parsing. The EPC is the "serial
 * number" of the tag — that's the thing we actually care about and
 * hand up to the ESP32. Everything else (RSSI, PC, CRC) is diagnostic. */
typedef struct {
    int8_t rssi;            /* dBm (signed) */
    uint8_t pc[2];          /* protocol control word */
    uint8_t epc[12];        /* EPC data (up to 12 bytes typical) */
    uint8_t epc_len;        /* actual EPC byte count */
    uint8_t crc[2];         /* CRC-16 from tag */
} yrm100_tag_t;

/* ── Generic response ───────────────────────────────────────────────
 * Holds a single parsed frame from the module. The parser in yrm100.c
 * fills one of these in from the UART stream, then higher-level helpers
 * unpack it into a yrm100_tag_t / region byte / whatever. */
typedef struct {
    uint8_t type;           /* frame type: 0x01 or 0x02 */
    uint8_t command;        /* echoed command code, or 0xFF for error */
    uint16_t param_len;     /* parameter length */
    uint8_t params[YRM100_MAX_FRAME_LEN];
    uint8_t error_code;     /* set when command == 0xFF */
} yrm100_response_t;

/* ── Platform UART callbacks (user must provide) ──────────────────── */
/* This is how we keep the driver portable. The caller fills in four
 * function pointers that know how to talk to whatever serial port they
 * have, and the driver just calls back into them. On our STM32 these
 * are yrm_uart_init/send/recv_byte/data_available over in main.c. */
typedef struct {
    void (*uart_init)(uint32_t baud);
    void (*uart_send)(const uint8_t *data, uint16_t len);
    uint8_t (*uart_recv_byte)(uint16_t timeout_ms);   /* returns 0 on timeout, else byte */
    uint8_t (*uart_data_available)(void);              /* nonzero if byte ready */
} yrm100_uart_t;

/* ── Handle ─────────────────────────────────────────────────────────
 * "Handle" is a fancy word for "the struct that represents one driver
 * instance". If we ever had two RFID readers we could have two of these. */
typedef struct {
    yrm100_uart_t uart;
    uint8_t rx_buf[YRM100_MAX_FRAME_LEN];
    uint16_t rx_len;
} yrm100_t;

/* ── Initialization ───────────────────────────────────────────────── */
void yrm100_init(yrm100_t *dev, const yrm100_uart_t *uart, uint32_t baud);

/* ── Module information ───────────────────────────────────────────── */
yrm100_status_t yrm100_get_hw_version(yrm100_t *dev, char *buf, uint8_t buf_len);
yrm100_status_t yrm100_get_sw_version(yrm100_t *dev, char *buf, uint8_t buf_len);
yrm100_status_t yrm100_get_manufacturer(yrm100_t *dev, char *buf, uint8_t buf_len);

/* ── Inventory ────────────────────────────────────────────────────── */
yrm100_status_t yrm100_single_inventory(yrm100_t *dev, yrm100_tag_t *tag);
yrm100_status_t yrm100_start_multi_inventory(yrm100_t *dev, uint16_t count);
yrm100_status_t yrm100_stop_inventory(yrm100_t *dev);
yrm100_status_t yrm100_poll_inventory(yrm100_t *dev, yrm100_tag_t *tag);

/* ── Select ───────────────────────────────────────────────────────── */
yrm100_status_t yrm100_set_select(yrm100_t *dev, uint8_t sel_param,
                                  uint32_t ptr, uint8_t mask_len,
                                  uint8_t truncate,
                                  const uint8_t *mask, uint8_t mask_bytes);
yrm100_status_t yrm100_set_select_mode(yrm100_t *dev, uint8_t mode);

/* ── Read / Write tag memory ──────────────────────────────────────── */
yrm100_status_t yrm100_read_tag(yrm100_t *dev, uint32_t access_password,
                                uint8_t membank, uint16_t addr,
                                uint16_t word_count,
                                uint8_t *data_out, uint16_t *data_len);

yrm100_status_t yrm100_write_tag(yrm100_t *dev, uint32_t access_password,
                                 uint8_t membank, uint16_t addr,
                                 uint16_t word_count,
                                 const uint8_t *data);

/* ── Lock / Kill ──────────────────────────────────────────────────── */
yrm100_status_t yrm100_lock_tag(yrm100_t *dev, uint32_t access_password,
                                uint8_t ld_msb, uint8_t ld_mid, uint8_t ld_lsb);
yrm100_status_t yrm100_kill_tag(yrm100_t *dev, uint32_t kill_password);

/* ── Configuration ────────────────────────────────────────────────── */
yrm100_status_t yrm100_set_baud(yrm100_t *dev, uint16_t baud_param);
yrm100_status_t yrm100_set_region(yrm100_t *dev, uint8_t region);
yrm100_status_t yrm100_get_region(yrm100_t *dev, uint8_t *region);
yrm100_status_t yrm100_set_channel(yrm100_t *dev, uint8_t channel);
yrm100_status_t yrm100_get_channel(yrm100_t *dev, uint8_t *channel);
yrm100_status_t yrm100_set_freq_hop(yrm100_t *dev);
yrm100_status_t yrm100_set_tx_power(yrm100_t *dev, uint16_t power);
yrm100_status_t yrm100_get_tx_power(yrm100_t *dev, uint16_t *power);

/* ── Power management ─────────────────────────────────────────────── */
yrm100_status_t yrm100_sleep(yrm100_t *dev);
yrm100_status_t yrm100_set_idle_time(yrm100_t *dev, uint8_t minutes);

/* ── Low-level (advanced) ─────────────────────────────────────────── */
uint8_t yrm100_checksum(const uint8_t *data, uint16_t len);
yrm100_status_t yrm100_send_cmd(yrm100_t *dev, uint8_t command,
                                const uint8_t *params, uint16_t param_len);
yrm100_status_t yrm100_recv_response(yrm100_t *dev, yrm100_response_t *resp,
                                     uint16_t timeout_ms);

#endif /* YRM100_H */
