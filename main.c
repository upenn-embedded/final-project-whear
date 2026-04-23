/* Whear — STM32F411RE bare-metal firmware
 *
 *   USART1  →  YRM100 RFID        (PA9 TX, PA10 RX)
 *   USART2  →  Debug via ST-Link VCOM  (PA2 TX, PA3 RX)
 *   USART6  →  ESP32 bridge        (PC6 TX, PC7 RX)
 *   SPI1    →  ST7735 1.8" TFT    (PA5 SCK, PA7 MOSI, PB6 DC, PB15 RST, PB5 CS)
 *   GPIO    →  READY pin (PA8, input from ESP32)
 *   GPIO    →  NeoPixel ring DIN (PB4, 12 LEDs, 800 kHz one-wire)
 */

#include <stdint.h>
#include <string.h>
#include "lib/yrm100/yrm100.h"
#include "lib/display/st7735.h"
#include "lib/display/lcd_gfx.h"
#include "lib/neopixel/neopixel.h"

/* ── Minimal STM32F411RE register map ────────────────────────────── */

typedef struct {
    volatile uint32_t CR, PLLCFGR, CFGR, CIR, AHB1RSTR, AHB2RSTR;
    uint32_t _pad1[2];
    volatile uint32_t APB1RSTR, APB2RSTR;
    uint32_t _pad2[2];
    volatile uint32_t AHB1ENR, AHB2ENR;
    uint32_t _pad3[2];
    volatile uint32_t APB1ENR, APB2ENR;
} RCC_t;
#define RCC ((RCC_t *)0x40023800)

typedef struct {
    volatile uint32_t MODER, OTYPER, OSPEEDR, PUPDR, IDR, ODR, BSRR, LCKR;
    volatile uint32_t AFR[2];
} GPIO_t;
#define GPIOA ((GPIO_t *)0x40020000)
#define GPIOB ((GPIO_t *)0x40020400)
#define GPIOC ((GPIO_t *)0x40020800)

typedef struct {
    volatile uint32_t SR, DR, BRR, CR1, CR2, CR3, GTPR;
} USART_t;
#define USART1 ((USART_t *)0x40011000)
#define USART2 ((USART_t *)0x40004400)
#define USART6 ((USART_t *)0x40011400)

typedef struct {
    volatile uint32_t CTRL, LOAD, VAL, CALIB;
} SYSTICK_t;
#define SYSTICK ((SYSTICK_t *)0xE000E010)

/* Bit defines */
#define USART_SR_TXE     (1 << 7)
#define USART_SR_TC      (1 << 6)
#define USART_SR_RXNE    (1 << 5)
#define USART_CR1_UE     (1 << 13)
#define USART_CR1_RXNEIE (1 << 5)
#define USART_CR1_TE     (1 << 3)
#define USART_CR1_RE     (1 << 2)

/* NVIC — USART1 IRQn = 37, so ISER1 bit 5 */
#define NVIC_ISER1 (*(volatile uint32_t *)0xE000E104)

/* ── Config ──────────────────────────────────────────────────────── */
#define HSI_FREQ            16000000UL
#define DISPLAY_INTERVAL_MS 200    /* TFT refresh + TTL prune cadence */
#define UPLINK_INTERVAL_MS  300    /* ESP32 / Firestore uplink + stats */
#define TAG_TTL_MS          2000   /* drop a tag if not re-seen within this —
                                      tighter = faster removal, but risks
                                      flicker on tags at the edge of range */
#define MAX_TAGS         20
#define UART_BAUD        115200
#define USARTDIV_115200  0x008B   /* 16MHz / (16 * 115200) ≈ 8.68 → Mant=8, Frac=11 */

/* ── SysTick millisecond timer ──────────────────────────────────── */

static volatile uint32_t ms_ticks;

void SysTick_Handler(void) { ms_ticks++; }

static uint32_t millis(void) { return ms_ticks; }

static void delay_ms(uint32_t ms) {
    uint32_t start = ms_ticks;
    while ((ms_ticks - start) < ms);
}

/* ── Clock / peripheral enable ──────────────────────────────────── */

static void clock_init(void) {
    /* HSI @ 16 MHz is the reset default — nothing to change */

    /* GPIOA, GPIOB, GPIOC */
    RCC->AHB1ENR  |= (1 << 0) | (1 << 1) | (1 << 2);
    /* USART2 (APB1) */
    RCC->APB1ENR  |= (1 << 17);
    /* USART1 (bit 4), USART6 (bit 5) on APB2 */
    RCC->APB2ENR  |= (1 << 4) | (1 << 5);

    /* SysTick: 1ms @ 16MHz */
    SYSTICK->LOAD = HSI_FREQ / 1000 - 1;
    SYSTICK->VAL  = 0;
    SYSTICK->CTRL = 0x7;   /* CPU clock, interrupt, enable */
}

/* ── GPIO configuration ─────────────────────────────────────────── */

static void gpio_set_af(GPIO_t *port, uint32_t pin, uint32_t af) {
    port->MODER &= ~(3u << (pin * 2));
    port->MODER |=  (2u << (pin * 2));
    uint32_t idx = pin / 8;
    uint32_t shift = (pin % 8) * 4;
    port->AFR[idx] &= ~(0xFu << shift);
    port->AFR[idx] |=  (af   << shift);
}

static void gpio_init(void) {
    /* USART2 TX/RX on PA2/PA3 (AF7) — ST-Link VCOM */
    gpio_set_af(GPIOA, 2, 7);
    gpio_set_af(GPIOA, 3, 7);

    /* USART1 TX/RX on PA9/PA10 (AF7) — YRM100 */
    gpio_set_af(GPIOA, 9, 7);
    gpio_set_af(GPIOA, 10, 7);
    /* PA10 (RX) pull-up so it idles high if line is flaky */
    GPIOA->PUPDR &= ~(3u << (10*2));
    GPIOA->PUPDR |=  (1u << (10*2));

    /* USART6 TX/RX on PC6/PC7 (AF8) — ESP32 bridge */
    gpio_set_af(GPIOC, 6, 8);
    gpio_set_af(GPIOC, 7, 8);
    /* PC7 (RX) pull-up */
    GPIOC->PUPDR &= ~(3u << (7*2));
    GPIOC->PUPDR |=  (1u << (7*2));

    /* PA8 as READY input with pull-down */
    GPIOA->MODER &= ~(3u << (8*2));
    GPIOA->PUPDR &= ~(3u << (8*2));
    GPIOA->PUPDR |=  (2u << (8*2));
}

/* ── USART2 (debug output via ST-Link VCOM) ─────────────────────── */

static void usart2_init(void) {
    USART2->BRR = USARTDIV_115200;
    USART2->CR1 = USART_CR1_UE | USART_CR1_TE | USART_CR1_RE;
}

static void dbg_putc(char c) {
    while (!(USART2->SR & USART_SR_TXE));
    USART2->DR = (uint8_t)c;
}

static void dbg_puts(const char *s) {
    while (*s) dbg_putc(*s++);
}

static void dbg_print_hex(uint8_t b) {
    static const char hex[] = "0123456789ABCDEF";
    dbg_putc(hex[b >> 4]);
    dbg_putc(hex[b & 0x0F]);
}

static void dbg_print_u8(uint8_t v) {
    if (v >= 100) dbg_putc('0' + v / 100);
    if (v >= 10)  dbg_putc('0' + (v / 10) % 10);
    dbg_putc('0' + v % 10);
}

/* ── USART1 callbacks for YRM100 ──────────────────────────────────
 * RX is interrupt-driven through a ring buffer so bytes aren't dropped while
 * the main loop is busy (display refresh, dbg prints, ESP32 uplink). Without
 * this, back-to-back YRM100 inventory notices desync the parser after ~12
 * tags and polling collapses. TX stays polled — we never send while the main
 * loop is doing something else. */

#define RX_BUF_SIZE 1024
#define RX_BUF_MASK (RX_BUF_SIZE - 1)
static volatile uint8_t  rx_buf[RX_BUF_SIZE];
static volatile uint16_t rx_head;
static volatile uint16_t rx_tail;
static volatile uint16_t rx_dropped;   /* incremented on buffer-full or USART OVR */

void USART1_IRQHandler(void) {
    uint32_t sr = USART1->SR;
    if (sr & USART_SR_RXNE) {
        uint8_t b = (uint8_t)USART1->DR;   /* reading DR clears RXNE (and OVR if set) */
        uint16_t next = (uint16_t)((rx_head + 1) & RX_BUF_MASK);
        if (next != rx_tail) {
            rx_buf[rx_head] = b;
            rx_head = next;
        } else {
            rx_dropped++;
        }
    }
}

static void yrm_uart_init(uint32_t baud) {
    (void)baud;
    rx_head = rx_tail = 0;
    rx_dropped = 0;
    USART1->BRR = USARTDIV_115200;
    USART1->CR1 = USART_CR1_UE | USART_CR1_TE | USART_CR1_RE | USART_CR1_RXNEIE;
    NVIC_ISER1  = (1u << 5);          /* enable USART1 IRQ (37) */
}

static void yrm_uart_send(const uint8_t *data, uint16_t len) {
    for (uint16_t i = 0; i < len; i++) {
        while (!(USART1->SR & USART_SR_TXE));
        USART1->DR = data[i];
    }
    while (!(USART1->SR & USART_SR_TC));
}

static uint8_t yrm_uart_recv_byte(uint16_t timeout_ms) {
    uint32_t start = millis();
    while ((millis() - start) < timeout_ms) {
        if (rx_head != rx_tail) {
            uint8_t b = rx_buf[rx_tail];
            rx_tail = (uint16_t)((rx_tail + 1) & RX_BUF_MASK);
            return b;
        }
    }
    return 0;
}

static uint8_t yrm_uart_data_available(void) {
    return (rx_head != rx_tail) ? 1 : 0;
}

/* ── USART6 (to ESP32) ──────────────────────────────────────────── */

static void esp_uart_init(void) {
    USART6->BRR = USARTDIV_115200;
    USART6->CR1 = USART_CR1_UE | USART_CR1_TE | USART_CR1_RE;
}

static void esp_uart_send_byte(uint8_t b) {
    while (!(USART6->SR & USART_SR_TXE));
    USART6->DR = b;
}

static void esp_send_tags(const yrm100_tag_t *tags, uint8_t count) {
    esp_uart_send_byte(0xAA);           /* start marker */
    esp_uart_send_byte(count);
    for (uint8_t i = 0; i < count; i++) {
        esp_uart_send_byte(tags[i].epc_len);
        for (uint8_t j = 0; j < tags[i].epc_len; j++)
            esp_uart_send_byte(tags[i].epc[j]);
    }
    esp_uart_send_byte(0x55);           /* end marker */
    while (!(USART6->SR & USART_SR_TC));
}

/* ── ESP32 READY pin ────────────────────────────────────────────── */

static uint8_t esp_ready(void) {
    return (GPIOA->IDR & (1u << 8)) ? 1 : 0;
}

/* ── Tag tracking with TTL ───────────────────────────────────────── */

static yrm100_tag_t seen_tags[MAX_TAGS];
static uint32_t     tag_last_seen[MAX_TAGS];   /* ms timestamp of last scan */
static uint8_t      num_tags;

static void print_tag(const yrm100_tag_t *tag);   /* fwd decl */

static uint8_t find_or_add_tag(const yrm100_tag_t *tag) {
    uint32_t now = millis();
    for (uint8_t i = 0; i < num_tags; i++) {
        if (seen_tags[i].epc_len == tag->epc_len &&
            memcmp(seen_tags[i].epc, tag->epc, tag->epc_len) == 0) {
            seen_tags[i].rssi = tag->rssi;
            tag_last_seen[i]  = now;
            return 0;
        }
    }
    if (num_tags < MAX_TAGS) {
        memcpy(&seen_tags[num_tags], tag, sizeof(*tag));
        tag_last_seen[num_tags] = now;
        num_tags++;
    }
    return 1;
}

/* Remove tags that haven't been re-scanned within TAG_TTL_MS */
static void prune_stale_tags(void) {
    uint32_t now = millis();
    uint8_t  write = 0;
    for (uint8_t read = 0; read < num_tags; read++) {
        if ((now - tag_last_seen[read]) < TAG_TTL_MS) {
            if (write != read) {
                seen_tags[write]     = seen_tags[read];
                tag_last_seen[write] = tag_last_seen[read];
            }
            write++;
        } else {
            dbg_puts("[stale] ");
            print_tag(&seen_tags[read]);
        }
    }
    num_tags = write;
}

/* ── Display helpers ────────────────────────────────────────────── */

static char *u8_to_str(uint8_t v, char *p) {
    if (v >= 100) *p++ = '0' + v / 100;
    if (v >= 10)  *p++ = '0' + (v / 10) % 10;
    *p++ = '0' + v % 10;
    return p;
}

/* Screen layout (160x128, landscape):
 *   y=4   "Whear" title, scale 2, centered (5 chars × 12 = 60, x=50)
 *   y=28  WiFi status, scale 1, centered
 *   y=50  big tag count, scale 5, centered
 *   y=94  "pieces detected" label, scale 1, centered (15 chars × 6 = 90, x=35) */
static void display_update(uint8_t tag_count, uint8_t connected) {
    /* Title */
    LCD_drawBlock(0, 0, LCD_WIDTH - 1, 19, BLACK);
    LCD_drawStringScaled(50, 4, "Whear", CYAN, BLACK, 2);

    /* ESP32 status. Post-init, READY is driven low by the ESP32 only during
     * Firestore uploads, so reflecting that as "Updating Cloud" is accurate
     * for the common case. */
    LCD_drawBlock(0, 24, LCD_WIDTH - 1, 35, BLACK);
    if (connected) {
        /* "WiFi Connected" — 14×6 = 84, x = 38 */
        LCD_drawString(38, 28, "WiFi Connected", GREEN, BLACK);
    } else {
        /* "Updating Cloud" — 14×6 = 84, x = 38 */
        LCD_drawString(38, 28, "Updating Cloud", YELLOW, BLACK);
    }

    /* Big count + small label */
    LCD_drawBlock(0, 44, LCD_WIDTH - 1, LCD_HEIGHT - 1, BLACK);

    char buf[4];
    char *p = u8_to_str(tag_count, buf);
    *p = '\0';
    uint8_t digits = (uint8_t)(p - buf);

    const uint8_t num_scale = 5;
    /* digits × 6 × scale gives width including trailing spacing; subtract
     * one scale's worth so the glyphs sit centered, not the column after. */
    uint8_t num_w = (uint8_t)(digits * 6 * num_scale - num_scale);
    uint8_t num_x = (uint8_t)((LCD_WIDTH - num_w) / 2);
    uint8_t num_y = 50;
    LCD_drawStringScaled(num_x, num_y, buf, WHITE, BLACK, num_scale);

    uint8_t label_y = (uint8_t)(num_y + 8 * num_scale + 4);
    LCD_drawString(35, label_y, "pieces detected", WHITE, BLACK);
}

/* ── NeoPixel ring animations ─────────────────────────────────────
 * The ring is in four states:
 *   1. Amber spinner  — during ESP wait + 10s warmup (non-blocking tick)
 *   2. Solid white 20% — steady "ready" indicator
 *   3. Green pulse    — blink when a new tag joins the set
 *   4. Red pulse      — blink when a tag falls out of the set (TTL)
 * The pulses are blocking (~400 ms each) but the USART1 RX ISR keeps
 * filling rx_buf the whole time, so no RFID bytes are dropped. */

static void ring_solid(neopixel_t *np, uint32_t color, uint8_t brightness) {
    neopixel_set_brightness(np, brightness);
    neopixel_fill(np, color);
    neopixel_show(np);
}

static void ring_off(neopixel_t *np) {
    neopixel_set_brightness(np, 255);
    neopixel_clear(np);
    neopixel_show(np);
}

static void ring_spinner_tick(neopixel_t *np, uint32_t color, uint32_t now_ms) {
    /* Head LED at full 50%, four trailing LEDs ramping down: 1/2, 1/4, 1/8,
     * 1/16 of head intensity. The longer tail makes rotation direction and
     * speed obvious even at the 100 ms step rate. */
    static const uint8_t trail_shifts[4] = { 1, 2, 3, 4 };
    neopixel_set_brightness(np, 128);
    uint8_t pos = (uint8_t)((now_ms / 100) % NEOPIXEL_NUM_LEDS);
    uint8_t r = (uint8_t)(color >> 16);
    uint8_t g = (uint8_t)(color >> 8);
    uint8_t b = (uint8_t)(color);

    for (uint16_t i = 0; i < NEOPIXEL_NUM_LEDS; i++) {
        neopixel_set_pixel_rgb(np, i, 0, 0, 0);
    }
    neopixel_set_pixel_rgb(np, pos, r, g, b);
    for (uint8_t k = 0; k < 4; k++) {
        uint8_t idx = (uint8_t)((pos + NEOPIXEL_NUM_LEDS - 1 - k) % NEOPIXEL_NUM_LEDS);
        uint8_t sh  = trail_shifts[k];
        neopixel_set_pixel_rgb(np, idx, (uint8_t)(r >> sh),
                                        (uint8_t)(g >> sh),
                                        (uint8_t)(b >> sh));
    }
    neopixel_show(np);
}

/* Non-blocking pulse: ring_pulse_start() stashes the request and returns
 * immediately; ring_pulse_tick() advances the animation each pass of the
 * main loop. This keeps the YRM100 poll and the ESP uplink from stalling
 * for the pulse's full duration. */
typedef struct {
    uint32_t color;
    uint32_t start_ms;
    uint32_t last_frame_ms;
    uint16_t duration_ms;
    uint8_t  active;
} ring_pulse_state_t;

static ring_pulse_state_t ring_pulse_state;

#define RING_PULSE_FRAME_MS 15    /* ≤100 Hz update cap; each show() briefly
                                     disables IRQs, so don't churn every tick */

static void ring_pulse_start(uint32_t color, uint16_t duration_ms) {
    ring_pulse_state.color         = color;
    ring_pulse_state.start_ms      = millis();
    ring_pulse_state.last_frame_ms = 0;
    ring_pulse_state.duration_ms   = duration_ms;
    ring_pulse_state.active        = 1;
}

static void ring_pulse_tick(neopixel_t *np) {
    if (!ring_pulse_state.active) return;

    uint32_t now     = millis();
    uint32_t elapsed = now - ring_pulse_state.start_ms;

    if (elapsed >= ring_pulse_state.duration_ms) {
        ring_off(np);
        ring_pulse_state.active = 0;
        return;
    }

    if ((now - ring_pulse_state.last_frame_ms) < RING_PULSE_FRAME_MS) return;
    ring_pulse_state.last_frame_ms = now;

    uint32_t half = ring_pulse_state.duration_ms / 2;
    uint32_t up   = (elapsed < half) ? elapsed
                                     : (ring_pulse_state.duration_ms - elapsed);
    uint8_t br = (uint8_t)((up * 255) / half);

    neopixel_set_brightness(np, br);
    neopixel_fill(np, ring_pulse_state.color);
    neopixel_show(np);
}

static void print_tag(const yrm100_tag_t *tag) {
    dbg_puts("EPC: ");
    for (uint8_t i = 0; i < tag->epc_len; i++) {
        dbg_print_hex(tag->epc[i]);
        if (i < tag->epc_len - 1) dbg_putc(' ');
    }
    dbg_puts("  RSSI: ");
    if (tag->rssi < 0) {
        dbg_putc('-');
        dbg_print_u8((uint8_t)(-tag->rssi));
    } else {
        dbg_print_u8((uint8_t)tag->rssi);
    }
    dbg_puts(" dBm\r\n");
}

/* ── Main ────────────────────────────────────────────────────────── */

int main(void) {
    clock_init();
    gpio_init();
    usart2_init();
    esp_uart_init();

    neopixel_t ring;
    neopixel_init(&ring, (neopixel_gpio_t *)GPIOB, 4);
    ring_spinner_tick(&ring, NEOPIXEL_COLOR(255, 100, 0), millis());

    lcd_init();
    LCD_setScreen(BLACK);
    LCD_drawStringScaled(50, 4, "Whear", CYAN, BLACK, 2);
    /* "booting..." — 10×6 = 60, x = 50 */
    LCD_drawString(50, 28, "booting...", WHITE, BLACK);

    dbg_puts("\r\n=== Whear STM32 RFID Scanner ===\r\n");
    dbg_puts("Waiting for ESP32 READY...\r\n");

    /* Wait up to 5s for the ESP32 to signal Wi-Fi ready. If it never does,
     * still bring up the RFID path — the send-to-ESP call is already gated
     * on esp_ready() in the main loop, so we degrade gracefully. */
    {
        uint32_t t0 = millis();
        while (!esp_ready() && (millis() - t0) < 5000) {
            ring_spinner_tick(&ring, NEOPIXEL_COLOR(255, 100, 0), millis());
            delay_ms(60);
        }
    }
    if (esp_ready()) {
        dbg_puts("ESP32 ready\r\n");
        dbg_puts("Holding 10s before starting RFID...\r\n");
        LCD_drawBlock(0, 28, LCD_WIDTH - 1, 35, BLACK);
        LCD_drawString(50, 28, "warming up 10s", WHITE, BLACK);
        {
            uint32_t t_warm = millis();
            while ((millis() - t_warm) < 10000) {
                ring_spinner_tick(&ring, NEOPIXEL_COLOR(255, 100, 0), millis());
                delay_ms(60);
            }
        }
    } else {
        dbg_puts("ESP32 not ready — proceeding without uplink\r\n");
    }
    ring_off(&ring);
    display_update(0, esp_ready());

    /* YRM100 setup */
    yrm100_t rfid;
    const yrm100_uart_t uart_cb = {
        .uart_init           = yrm_uart_init,
        .uart_send           = yrm_uart_send,
        .uart_recv_byte      = yrm_uart_recv_byte,
        .uart_data_available = yrm_uart_data_available,
    };
    yrm100_init(&rfid, &uart_cb, UART_BAUD);
    delay_ms(500);

    /* Raw RX diagnostic: 2s window, dump any byte that arrives on USART1.
       Bytes are drained into rx_buf by the ISR — we read from there. */
    dbg_puts("[diag] raw RX window (2s)...\r\n");
    {
        uint32_t t0 = millis();
        uint32_t got = 0;
        while ((millis() - t0) < 2000) {
            if (rx_head != rx_tail) {
                uint8_t b = rx_buf[rx_tail];
                rx_tail = (uint16_t)((rx_tail + 1) & RX_BUF_MASK);
                dbg_print_hex(b);
                dbg_putc(' ');
                got++;
            }
        }
        dbg_puts("\r\n[diag] got "); dbg_print_u8(got > 255 ? 255 : got);
        dbg_puts(" bytes\r\n");
    }

    yrm100_status_t s;
    s = yrm100_set_region(&rfid, YRM100_REGION_US);
    dbg_puts("set_region: "); dbg_print_u8(s); dbg_puts("\r\n");

    s = yrm100_set_tx_power(&rfid, YRM100_POWER_2600);
    dbg_puts("set_tx_power: "); dbg_print_u8(s); dbg_puts("\r\n");

    dbg_puts("Starting multi-inventory...\r\n\r\n");
    yrm100_start_multi_inventory(&rfid, 0xFFFF);

    uint32_t last_uplink  = millis();
    uint32_t last_display = millis();
    uint32_t poll_ok = 0, poll_timeout = 0, poll_err = 0;

    while (1) {
        yrm100_tag_t tag;
        s = yrm100_poll_inventory(&rfid, &tag);

        if (s == YRM100_OK) {
            poll_ok++;
            if (find_or_add_tag(&tag)) {
                dbg_puts("[NEW] ");
                print_tag(&tag);
                ring_pulse_start(NEOPIXEL_COLOR(0, 255, 0), 400);
            }
        } else if (s == YRM100_ERR_TIMEOUT) {
            poll_timeout++;
        } else {
            poll_err++;
        }

        /* TTL prune + LCD refresh — both run on the fast cadence so stale
         * tags drop within TAG_TTL_MS + DISPLAY_INTERVAL_MS of leaving range. */
        if ((millis() - last_display) >= DISPLAY_INTERVAL_MS) {
            uint8_t tags_before_prune = num_tags;
            prune_stale_tags();
            if (num_tags < tags_before_prune) {
                ring_pulse_start(NEOPIXEL_COLOR(255, 0, 0), 400);
            }
            display_update(num_tags, esp_ready());
            last_display = millis();
        }

        /* Advance any in-flight ring pulse — non-blocking, so the poll loop
         * and the uplink timer keep ticking while the fade animates. */
        ring_pulse_tick(&ring);

        /* Stats + ESP uplink. The ESP is naturally gated on esp_ready() so
         * back-to-back sends are skipped while Firestore is still flushing
         * the previous batch. */
        if ((millis() - last_uplink) >= UPLINK_INTERVAL_MS) {
            dbg_puts("[poll] ok=");   dbg_print_u8(poll_ok > 255 ? 255 : poll_ok);
            dbg_puts(" to=");         dbg_print_u8(poll_timeout > 255 ? 255 : poll_timeout);
            dbg_puts(" err=");        dbg_print_u8(poll_err > 255 ? 255 : poll_err);
            dbg_puts(" rxdrop=");     dbg_print_u8(rx_dropped > 255 ? 255 : rx_dropped);
            dbg_puts("\r\n");
            poll_ok = poll_timeout = poll_err = 0;
            rx_dropped = 0;

            if (esp_ready()) {
                dbg_puts("[UART] sending ");
                dbg_print_u8(num_tags);
                dbg_puts(" tags\r\n");
                esp_send_tags(seen_tags, num_tags);
            }

            last_uplink = millis();
        }
    }
}
