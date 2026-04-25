/* Whear — STM32F411RE bare-metal firmware
 *
 *   USART1  →  YRM100 RFID        (PA9 TX, PA10 RX)
 *   USART2  →  Debug via ST-Link VCOM  (PA2 TX, PA3 RX)
 *   USART6  →  Wifi Module ESP32 bridge        (PC6 TX, PC7 RX)
 *   SPI1    →  ST7735 1.8" TFT    (PA5 SCK, PA7 MOSI, PB6 DC, PB15 RST, PB5 CS)
 *   GPIO    →  READY pin (PA8, input from ESP32)
 *   GPIO    →  NeoPixel ring DIN (PB4, 12 LEDs, 800 kHz one-wire)
 *
 * === Demo cheat sheet (student notes) ===
 * This is the STM32 side of the project. During the demo here is the
 * order of things that happen once we plug it in:
 *   1. The chip boots, we set up the clocks and all the UARTs.
 *   2. We turn the little NeoPixel ring amber while we wait for the
 *      ESP32 to join WiFi (the ESP32 tells us it's ready by pulling
 *      PA8 high — that's the "READY pin").
 *   3. Once WiFi is up we talk to the YRM100 RFID reader over UART1
 *      and tell it to start continuously scanning for tags.
 *   4. In the main loop we read tag notifications from the YRM100,
 *      keep a table of "currently present" tags, and every 300 ms we
 *      send the whole table to the ESP32 over UART6. The ESP32 then
 *      syncs that list up to Firestore, and the iOS app sees it.
 *   5. Green ring pulse = new tag just joined. Red ring pulse = a tag
 *      disappeared (its TTL expired). The LCD shows the live count.
 */

#include <stdint.h>
#include <string.h>
#include "lib/yrm100/yrm100.h"
#include "lib/display/st7735.h"
#include "lib/display/lcd_gfx.h"
#include "lib/neopixel/neopixel.h"

/* ── Minimal STM32F411RE register map ──────────────────────────────
 * Note: We are not using the ST HAL, so we have to define where each
 * peripheral's registers live in memory ourselves. The addresses here
 * all come straight from the STM32F411 reference manual (RM0383).
 * Each struct matches the register layout so e.g. RCC->AHB1ENR is
 * just a normal C member access that points to the right MMIO.
 *
 * The pattern we use a lot: declare a struct where every field is a
 * volatile uint32_t in the exact order the datasheet lists registers,
 * then cast the base peripheral address to a pointer of that type. Now
 * "RCC->AHB1ENR" compiles down to a single store at the right address
 * — no HAL, no magic, just pointer arithmetic we can reason about. */

/* RCC = Reset & Clock Control. It's what turns on the clocks for every
 * peripheral we want to use. If we forget to flip the right ENR bit the
 * peripheral silently does nothing, which cost me a solid hour of my life
 * the first time I tried to use USART1. The _pad fields are just filler
 * for reserved words so the struct offsets line up with the manual. */
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

/* GPIO = General-Purpose Input/Output. Each port has the same layout,
 * so we only define the struct once and then hand out a pointer per
 * port (A/B/C). MODER picks input/output/alternate, AFR picks which
 * peripheral "owns" the pin when we go into alternate-function mode
 * (e.g. USART1 TX on PA9 lives under AF7). */
typedef struct {
    volatile uint32_t MODER, OTYPER, OSPEEDR, PUPDR, IDR, ODR, BSRR, LCKR;
    volatile uint32_t AFR[2];
} GPIO_t;
#define GPIOA ((GPIO_t *)0x40020000)
#define GPIOB ((GPIO_t *)0x40020400)
#define GPIOC ((GPIO_t *)0x40020800)

/* USART = Universal Sync/Async Receiver/Transmitter — aka "the serial
 * port". We use three of them: USART2 is wired to the ST-Link's USB
 * serial so we can printf debug messages to our laptop, USART1 talks
 * to the RFID reader, USART6 talks to the ESP32 WiFi module. */
typedef struct {
    volatile uint32_t SR, DR, BRR, CR1, CR2, CR3, GTPR;
} USART_t;
#define USART1 ((USART_t *)0x40011000)
#define USART2 ((USART_t *)0x40004400)
#define USART6 ((USART_t *)0x40011400)

/* SysTick is the 24-bit timer built into the Cortex-M core itself (so
 * it's at a fixed Cortex address, not on one of the STM32 buses). We
 * program it to fire once every millisecond and use it as our wall
 * clock for all the timing stuff in the main loop. */
typedef struct {
    volatile uint32_t CTRL, LOAD, VAL, CALIB;
} SYSTICK_t;
#define SYSTICK ((SYSTICK_t *)0xE000E010)

/* Bit defines — these are the bit positions inside the USART registers
 * we care about. TXE = "transmit register empty, ok to write next byte",
 * TC = "transmission complete, line is idle", RXNE = "a new byte just
 * landed, go read it". UE/TE/RE are the enable bits in CR1. */
#define USART_SR_TXE     (1 << 7)
#define USART_SR_TC      (1 << 6)
#define USART_SR_RXNE    (1 << 5)
#define USART_CR1_UE     (1 << 13)
#define USART_CR1_RXNEIE (1 << 5)
#define USART_CR1_TE     (1 << 3)
#define USART_CR1_RE     (1 << 2)

/* NVIC = Nested Vector Interrupt Controller. To make an interrupt
 * actually fire we have to (1) enable it in the peripheral, and (2)
 * unmask it in the NVIC by setting the matching bit in the right
 * ISER register. USART1's IRQn is 37, and 37 lives in ISER1 at bit 5. */
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

/* ── SysTick millisecond timer ────────────────────────────────────
 * SysTick is a tiny timer that's built into every Cortex-M core. We
 * tell it to fire an interrupt every 1 ms. Each interrupt we bump the
 * ms_ticks counter, which gives us a simple millis() function just
 * like on Arduino. The whole main loop uses this for timing (TTL
 * pruning, uplink cadence, display refresh, etc). */

static volatile uint32_t ms_ticks;

void SysTick_Handler(void) { ms_ticks++; }

static uint32_t millis(void) { return ms_ticks; }

static void delay_ms(uint32_t ms) {
    uint32_t start = ms_ticks;
    while ((ms_ticks - start) < ms);
}

/* ── Clock / peripheral enable ────────────────────────────────────
 * This is the very first thing main() calls. The chip comes out of
 * reset with every peripheral clock-gated off to save power, so any
 * attempt to use GPIOA or USART1 before flipping its bit in RCC will
 * just quietly do nothing (which is a horrible thing to debug). We
 * enable everything we need up front in one place so it's obvious. */

static void clock_init(void) {
    /* HSI = High-Speed Internal oscillator, 16 MHz. It's the default
     * clock source after reset, and we don't bother spinning up the
     * PLL because 16 MHz is plenty for what we're doing. All the
     * peripheral dividers and our SysTick LOAD are derived from this. */

    /* Enable the clocks on the three GPIO ports we actually use.
     * Bit 0 = GPIOA, bit 1 = GPIOB, bit 2 = GPIOC (see RM0383). */
    RCC->AHB1ENR  |= (1 << 0) | (1 << 1) | (1 << 2);
    /* USART2 lives on APB1 (the slow bus). Its enable bit is 17. */
    RCC->APB1ENR  |= (1 << 17);
    /* USART1 (bit 4) and USART6 (bit 5) share APB2 (the fast bus). */
    RCC->APB2ENR  |= (1 << 4) | (1 << 5);

    /* SysTick setup: count down from HSI/1000 - 1 = 15999 every tick,
     * and when it hits zero roll over + fire the SysTick_Handler. At
     * 16 MHz that's exactly one interrupt per millisecond. CTRL = 0x7
     * means: use the CPU clock (not /8), enable the interrupt, enable
     * the counter. Starting VAL at 0 just forces a reload on the first
     * cycle so we get clean timing from t=0. */
    SYSTICK->LOAD = HSI_FREQ / 1000 - 1;
    SYSTICK->VAL  = 0;
    SYSTICK->CTRL = 0x7;   /* CPU clock, interrupt, enable */
}

/* ── GPIO configuration ───────────────────────────────────────────
 * The STM32 has a TON of pin-mux options. Each GPIO pin can be an input,
 * a push-pull output, an open-drain output, an analog pin, OR any of 16
 * "alternate functions" (AF0..AF15) that route it to an on-chip peripheral
 * like a UART or SPI. Which peripheral gets a given AF slot is a fixed
 * table in the datasheet — we don't get to pick, we just look it up. */

/* Helper for the common case: "put this pin into alternate-function mode
 * and select AF number `af`". MODER is 2 bits per pin (10 = alternate fn),
 * AFR is split into two 32-bit registers of 4 bits per pin (8 pins each),
 * so we figure out which AFR half to poke and which nibble to write. */
static void gpio_set_af(GPIO_t *port, uint32_t pin, uint32_t af) {
    port->MODER &= ~(3u << (pin * 2));
    port->MODER |=  (2u << (pin * 2));
    uint32_t idx = pin / 8;
    uint32_t shift = (pin % 8) * 4;
    port->AFR[idx] &= ~(0xFu << shift);
    port->AFR[idx] |=  (af   << shift);
}

static void gpio_init(void) {
    /* USART2 TX/RX on PA2/PA3 (AF7) — ST-Link VCOM.
     * The Nucleo board has the ST-Link's USB-serial tied to PA2/PA3,
     * so if we put USART2 on those pins we get free printf over USB
     * with no extra wiring. AF7 is what the datasheet assigns to UART. */
    gpio_set_af(GPIOA, 2, 7);
    gpio_set_af(GPIOA, 3, 7);

    /* USART1 TX/RX on PA9/PA10 (AF7) — YRM100 RFID reader. */
    gpio_set_af(GPIOA, 9, 7);
    gpio_set_af(GPIOA, 10, 7);
    /* Pull PA10 (the RX line) up internally. UART lines idle HIGH
     * when nothing is talking, and if the wire is a little flaky or
     * the RFID module is cold, a missing pull-up would let the line
     * float around and generate garbage start bits. The pull-up is
     * the belt-and-suspenders move. */
    GPIOA->PUPDR &= ~(3u << (10*2));
    GPIOA->PUPDR |=  (1u << (10*2));

    /* USART6 TX/RX on PC6/PC7 (AF8) — ESP32 WiFi bridge. Different AF
     * than USART1/2 because USART6 uses AF8 on this chip. */
    gpio_set_af(GPIOC, 6, 8);
    gpio_set_af(GPIOC, 7, 8);
    /* Same pull-up trick on our RX line to the ESP32. */
    GPIOC->PUPDR &= ~(3u << (7*2));
    GPIOC->PUPDR |=  (1u << (7*2));

    /* PA8 is the "READY" signal coming back from the ESP32. We configure
     * it as a plain input (MODER = 00) with a pull-down (PUPDR = 10), so
     * if the ESP32 is unplugged or hasn't booted yet the line reads LOW
     * by default. Once WiFi is up the ESP32 drives the line HIGH. */
    GPIOA->MODER &= ~(3u << (8*2));
    GPIOA->PUPDR &= ~(3u << (8*2));
    GPIOA->PUPDR |=  (2u << (8*2));
}

/* ── USART2 (debug output via ST-Link VCOM) ───────────────────────
 * Setting BRR to USARTDIV_115200 programs the baud-rate divider so the
 * UART runs at 115200 baud. CR1 flips on the USART itself (UE) plus the
 * transmitter (TE) and receiver (RE). We don't enable any interrupts here
 * because we're only using USART2 for polled debug prints. */
static void usart2_init(void) {
    USART2->BRR = USARTDIV_115200;
    USART2->CR1 = USART_CR1_UE | USART_CR1_TE | USART_CR1_RE;
}

/* dbg_putc: push a single char out USART2. The hardware has a 1-byte TX
 * "holding register" (DR), and the TXE flag goes high when that register
 * is empty and ready for the next byte. So we spin until TXE then store
 * the byte — standard polled UART pattern from class. */
static void dbg_putc(char c) {
    while (!(USART2->SR & USART_SR_TXE));
    USART2->DR = (uint8_t)c;
}

/* Thin wrapper so we can write dbg_puts("hello\r\n") instead of looping
 * ourselves everywhere. Just walks a C string until the null terminator. */
static void dbg_puts(const char *s) {
    while (*s) dbg_putc(*s++);
}

/* Print one byte as two ASCII hex digits (e.g. 0xA3 → "A3"). Used all
 * over the place when dumping RFID frames and EPC values to the terminal. */
static void dbg_print_hex(uint8_t b) {
    static const char hex[] = "0123456789ABCDEF";
    dbg_putc(hex[b >> 4]);
    dbg_putc(hex[b & 0x0F]);
}

/* Mini itoa for unsigned bytes so we don't have to drag printf into the
 * binary. Just emits the digits 0..255, no zero-padding, no newline. */
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

/* This is the actual interrupt handler that the vector table in
 * startup.c points at. Every time a byte arrives on USART1 the CPU jumps
 * here, we grab the byte, and stuff it into the ring buffer. Reading DR
 * is what tells the peripheral "I've seen this byte, clear your RXNE flag".
 * If the buffer is full (head+1 == tail) we just bump a dropped counter
 * instead of overwriting good data — that way we can spot it in logs. */
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

/* The YRM100 library expects us to provide four callback functions so
 * that it doesn't care which MCU it's running on. yrm_uart_init is the
 * setup one — we reset the ring buffer pointers, set baud, and flip on
 * the RXNE interrupt (CR1 bit 5) + enable the NVIC line. From this
 * point on every incoming byte goes through the ISR above. */
static void yrm_uart_init(uint32_t baud) {
    (void)baud;
    rx_head = rx_tail = 0;
    rx_dropped = 0;
    USART1->BRR = USARTDIV_115200;
    USART1->CR1 = USART_CR1_UE | USART_CR1_TE | USART_CR1_RE | USART_CR1_RXNEIE;
    NVIC_ISER1  = (1u << 5);          /* enable USART1 IRQ (37) */
}

/* Send a buffer out USART1 byte-by-byte. Same polled pattern as dbg_putc,
 * just in a loop. The final wait on TC ("Transmission Complete") makes
 * sure the LAST byte has actually finished shifting out onto the wire
 * before we return — otherwise the caller might cut power or reset the
 * line mid-byte and the RFID module would miss the tail of the frame. */
static void yrm_uart_send(const uint8_t *data, uint16_t len) {
    for (uint16_t i = 0; i < len; i++) {
        while (!(USART1->SR & USART_SR_TXE));
        USART1->DR = data[i];
    }
    while (!(USART1->SR & USART_SR_TC));
}

/* Pop one byte off the ring buffer (the side that's been filling up in
 * the ISR). If nothing is there we spin for up to timeout_ms using our
 * SysTick clock, then give up and return 0. Returning 0 on timeout is a
 * little sketchy since 0 is a valid byte, but the YRM100 protocol has
 * checksums/framing that catch it, so in practice we're fine. */
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

/* "Is there at least one byte waiting?" Used by the YRM100 library to
 * peek without blocking — head==tail means the ring is empty. */
static uint8_t yrm_uart_data_available(void) {
    return (rx_head != rx_tail) ? 1 : 0;
}

/* ── USART6 (to ESP32) ──────────────────────────────────────────── */

/* Same style as USART2 init — polled mode only since we're the talker
 * here, not the listener. The ESP32 side handles its own RX buffering. */
static void esp_uart_init(void) {
    USART6->BRR = USARTDIV_115200;
    USART6->CR1 = USART_CR1_UE | USART_CR1_TE | USART_CR1_RE;
}

static void esp_uart_send_byte(uint8_t b) {
    while (!(USART6->SR & USART_SR_TXE));
    USART6->DR = b;
}

/* Our tiny framing protocol from STM32 → ESP32. Because the ESP32 might
 * pick us up mid-stream we bookend each packet with easy-to-recognise
 * markers (0xAA at the start, 0x55 at the end) and include a count so
 * the ESP32 knows how many tag records to expect. Per tag we send:
 *   [EPC length byte][EPC bytes...]
 * That's it — no RSSI, no checksum, deliberately minimal. If the ESP32
 * sees anything weird it just drops the frame and waits for the next one. */
static void esp_send_tags(const yrm100_tag_t *tags, uint8_t count) {
    esp_uart_send_byte(0xAA);           /* start marker */
    esp_uart_send_byte(count);
    for (uint8_t i = 0; i < count; i++) {
        esp_uart_send_byte(tags[i].epc_len);
        for (uint8_t j = 0; j < tags[i].epc_len; j++)
            esp_uart_send_byte(tags[i].epc[j]);
    }
    esp_uart_send_byte(0x55);           /* end marker */
    /* Wait for the last byte to actually clock out before returning. */
    while (!(USART6->SR & USART_SR_TC));
}

/* ── ESP32 READY pin ──────────────────────────────────────────────
 * The ESP32 drives PA8 HIGH when it's got WiFi and is ready to accept
 * frames, and LOW while it's mid-upload to Firestore. We read it by
 * masking bit 8 of the input-data register (IDR) for GPIOA. */

static uint8_t esp_ready(void) {
    return (GPIOA->IDR & (1u << 8)) ? 1 : 0;
}

/* ── Tag tracking with TTL ─────────────────────────────────────────
 * The RFID reader fires off an inventory "notice" every time it sees
 * a tag — which for a single tag in range can be ~30 times per second.
 * We don't want to spam the ESP32 with every single read, so we keep
 * a little table of "tags I've recently seen" and a timestamp for when
 * we last saw each one. When a tag stops showing up for TAG_TTL_MS we
 * consider it "left" and drop it from the table. */

static yrm100_tag_t seen_tags[MAX_TAGS];
static uint32_t     tag_last_seen[MAX_TAGS];   /* ms timestamp of last scan */
static uint8_t      num_tags;

static void print_tag(const yrm100_tag_t *tag);   /* fwd decl */

/* Try to find this tag in our table. If it's already there, just refresh
 * its timestamp and RSSI and return 0 (meaning "nothing new"). If it's a
 * tag we haven't seen before, append it and return 1 so main() can trigger
 * the "new tag!" green pulse on the ring. Linear search is fine since
 * MAX_TAGS is tiny (20) and this only runs on poll hits. */
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

/* Walk the table and kick out anyone whose last-seen timestamp is older
 * than TAG_TTL_MS. Classic "two-pointer" compaction: read marches through
 * every entry, write only advances when the entry survives, so at the end
 * the first `write` slots are the keepers and we just truncate the count.
 * Each evicted tag gets a log line so we can see removals in the terminal. */
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

/* Tiny unsigned-byte-to-string. We avoid printf/snprintf because they
 * pull in a big chunk of newlib and eat flash for no reason — this is
 * a microcontroller, every kB counts. Writes digits into the caller's
 * buffer and returns the "one past the last" pointer so callers can
 * null-terminate or keep appending. */
static char *u8_to_str(uint8_t v, char *p) {
    if (v >= 100) *p++ = '0' + v / 100;
    if (v >= 10)  *p++ = '0' + (v / 10) % 10;
    *p++ = '0' + v % 10;
    return p;
}

/* display_update redraws the whole LCD: title at the top, WiFi status
 * in the middle, giant tag count, and a little label underneath. The
 * screen is 160×128 in landscape. We draw a black block to erase each
 * region before re-drawing, otherwise the digits from the previous count
 * would still be on-screen (the driver doesn't auto-clear). */

/* Screen layout (160x128, landscape):
 *   y=4   "Whear" title, scale 2, centered (5 chars × 12 = 60, x=50)
 *   y=28  WiFi status, scale 1, centered
 *   y=50  big tag count, scale 5, centered
 *   y=94  "pieces detected" label, scale 1, centered (15 chars × 6 = 90, x=35) */
static void display_update(uint8_t tag_count, uint8_t connected) {
    /* Title row. Wipe it first so we don't leave ghost pixels if some
     * previous draw landed in this stripe. */
    LCD_drawBlock(0, 0, LCD_WIDTH - 1, 19, BLACK);
    LCD_drawStringScaled(50, 4, "Whear", CYAN, BLACK, 2);

    /* ESP32 status. Post-init, READY is driven low by the ESP32 only during
     * Firestore uploads, so reflecting that as "Updating Cloud" is accurate
     * for the common case. (During initial boot the ESP32 holds it low
     * until WiFi connects, but by the time we're calling display_update
     * in a loop we're already past that.) */
    LCD_drawBlock(0, 24, LCD_WIDTH - 1, 35, BLACK);
    if (connected) {
        /* "WiFi Connected" — 14×6 = 84, x = 38 */
        LCD_drawString(38, 28, "WiFi Connected", GREEN, BLACK);
    } else {
        /* "Updating Cloud" — 14×6 = 84, x = 38 */
        LCD_drawString(38, 28, "Updating Cloud", YELLOW, BLACK);
    }

    /* Wipe the entire bottom two-thirds and redraw the big count + label.
     * It's a little wasteful but the whole screen only takes ~20 ms to
     * repaint and we only do this every DISPLAY_INTERVAL_MS = 200 ms. */
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

    /* Small caption below the big number. 8*scale is the glyph height,
     * +4 is a few pixels of air between the number and the label. */
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

/* All 12 LEDs to the same color and brightness, then push the buffer out
 * to the ring. Used when we just want the ring to sit there glowing. */
static void ring_solid(neopixel_t *np, uint32_t color, uint8_t brightness) {
    neopixel_set_brightness(np, brightness);
    neopixel_fill(np, color);
    neopixel_show(np);
}

/* Turn every LED off. Brightness gets reset to 255 first so that when
 * we next set a color we don't get a surprise "wait why is it dim" from
 * whatever brightness was set during the last pulse. */
static void ring_off(neopixel_t *np) {
    neopixel_set_brightness(np, 255);
    neopixel_clear(np);
    neopixel_show(np);
}

/* ring_spinner_tick draws one frame of our "loading" animation. Given
 * the current ms timestamp it figures out which LED should be the "head"
 * (moves one position every 100 ms) and paints a head + four dimmer
 * trailing LEDs behind it. Call this repeatedly in a loop and it looks
 * like a comet chasing itself around the ring. */
static void ring_spinner_tick(neopixel_t *np, uint32_t color, uint32_t now_ms) {
    /* Head LED at full 50%, four trailing LEDs ramping down: 1/2, 1/4, 1/8,
     * 1/16 of head intensity. Right-shifting by 1, 2, 3, 4 is a cheap way
     * to halve brightness without actually multiplying. The longer tail
     * makes rotation direction and speed obvious even at 100 ms per step. */
    static const uint8_t trail_shifts[4] = { 1, 2, 3, 4 };
    neopixel_set_brightness(np, 128);
    uint8_t pos = (uint8_t)((now_ms / 100) % NEOPIXEL_NUM_LEDS);
    /* Unpack the 0x00RRGGBB color into its three channels. */
    uint8_t r = (uint8_t)(color >> 16);
    uint8_t g = (uint8_t)(color >> 8);
    uint8_t b = (uint8_t)(color);

    /* Clear the framebuffer first so we're not building on top of the
     * previous frame. */
    for (uint16_t i = 0; i < NEOPIXEL_NUM_LEDS; i++) {
        neopixel_set_pixel_rgb(np, i, 0, 0, 0);
    }
    /* Bright head LED. */
    neopixel_set_pixel_rgb(np, pos, r, g, b);
    /* Four trailing LEDs behind it, each one dimmer than the last.
     * We go "backwards" around the ring (pos-1, pos-2, ...) with the
     * +NEOPIXEL_NUM_LEDS - 1 trick so the modulo doesn't underflow. */
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

/* "Hey ring, please pulse `color` for `duration_ms` starting now, don't
 * block, I'll come back and tick you later." Just stashes the request. */
static void ring_pulse_start(uint32_t color, uint16_t duration_ms) {
    ring_pulse_state.color         = color;
    ring_pulse_state.start_ms      = millis();
    ring_pulse_state.last_frame_ms = 0;
    ring_pulse_state.duration_ms   = duration_ms;
    ring_pulse_state.active        = 1;
}

/* Called every pass of the main loop. If there's an active pulse it
 * computes the right brightness for the current moment in time and
 * repaints the ring. The pulse goes: dark → full bright at the midpoint
 * → dark again. When the requested duration runs out we turn the ring
 * off and clear the `active` flag so the next main-loop pass skips us. */
static void ring_pulse_tick(neopixel_t *np) {
    if (!ring_pulse_state.active) return;

    uint32_t now     = millis();
    uint32_t elapsed = now - ring_pulse_state.start_ms;

    /* Pulse done — turn the ring off and shut down. */
    if (elapsed >= ring_pulse_state.duration_ms) {
        ring_off(np);
        ring_pulse_state.active = 0;
        return;
    }

    /* Throttle framerate so we don't hammer neopixel_show() every iteration
     * (each show() disables IRQs for ~360 µs — not free). */
    if ((now - ring_pulse_state.last_frame_ms) < RING_PULSE_FRAME_MS) return;
    ring_pulse_state.last_frame_ms = now;

    /* Triangle wave: `up` = 0 at the ends, = half at the peak. Scaling
     * that to 0..255 gives us a nice symmetric fade in/out. */
    uint32_t half = ring_pulse_state.duration_ms / 2;
    uint32_t up   = (elapsed < half) ? elapsed
                                     : (ring_pulse_state.duration_ms - elapsed);
    uint8_t br = (uint8_t)((up * 255) / half);

    neopixel_set_brightness(np, br);
    neopixel_fill(np, ring_pulse_state.color);
    neopixel_show(np);
}

/* Debug dump of one tag: its EPC bytes in hex followed by the RSSI in
 * dBm. RSSI comes out of the YRM100 as a signed byte — negative numbers
 * mean "weaker signal". Since our dbg_print_u8 only does unsigned we
 * print the '-' and then the absolute value by hand. */
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

/* ── Main ──────────────────────────────────────────────────────────
 * Every embedded program is basically "setup; loop forever" and this
 * one is no different. Setup: bring up clocks, GPIOs, UARTs, the LCD,
 * the LED ring, wait for the ESP32 to have WiFi, then configure the
 * RFID reader. After that we just sit in a while(1) polling for tags,
 * pruning stale ones, refreshing the display, and shipping the list
 * to the ESP32 every UPLINK_INTERVAL_MS. */

int main(void) {
    /* Bring the MCU up. Order matters: clocks must come before we touch
     * any peripheral, and GPIO AF muxing must come before we use the UARTs. */
    clock_init();
    gpio_init();
    usart2_init();
    esp_uart_init();

    /* Fire up the LED ring on PB4 and start an amber "loading" spinner
     * so the user knows the board is alive even before the LCD inits. */
    neopixel_t ring;
    neopixel_init(&ring, (neopixel_gpio_t *)GPIOB, 4);
    ring_spinner_tick(&ring, NEOPIXEL_COLOR(255, 100, 0), millis());

    /* Bring up the ST7735 LCD and show a placeholder "booting..." screen. */
    lcd_init();
    LCD_setScreen(BLACK);
    LCD_drawStringScaled(50, 4, "Whear", CYAN, BLACK, 2);
    /* "booting..." — 10×6 = 60, x = 50 */
    LCD_drawString(50, 28, "booting...", WHITE, BLACK);

    /* Hello world on the debug UART so the ST-Link terminal shows we're up. */
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

    /* YRM100 setup. The driver is written to be portable so it doesn't
     * know about our specific UART. We hand it a struct of four function
     * pointers (init/send/recv/available) that it will call into whenever
     * it needs to move bytes — this is basically a poor man's interface. */
    yrm100_t rfid;
    const yrm100_uart_t uart_cb = {
        .uart_init           = yrm_uart_init,
        .uart_send           = yrm_uart_send,
        .uart_recv_byte      = yrm_uart_recv_byte,
        .uart_data_available = yrm_uart_data_available,
    };
    yrm100_init(&rfid, &uart_cb, UART_BAUD);
    /* Give the RFID module a moment to finish its own internal boot before
     * we start shoving config commands at it. 500 ms is empirical — we
     * hit the occasional "module ignores first command" without it. */
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

    /* Configure the RFID module. Region is legally important — pick US
     * because that's where we're demoing. TX power at 26 dBm is the
     * module max; we found that anything lower was unreliable past
     * about 30 cm for the tags we're using. */
    yrm100_status_t s;
    s = yrm100_set_region(&rfid, YRM100_REGION_US);
    dbg_puts("set_region: "); dbg_print_u8(s); dbg_puts("\r\n");

    s = yrm100_set_tx_power(&rfid, YRM100_POWER_2600);
    dbg_puts("set_tx_power: "); dbg_print_u8(s); dbg_puts("\r\n");

    /* Kick off "multi-inventory" mode: the module will spam us with an
     * inventory notice every time it sees a tag, up to 0xFFFF rounds
     * (effectively forever). We don't have to poll for each read — we
     * just keep calling yrm100_poll_inventory() which drains one frame
     * at a time from the incoming stream. */
    dbg_puts("Starting multi-inventory...\r\n\r\n");
    yrm100_start_multi_inventory(&rfid, 0xFFFF);

    /* Bookkeeping for the main loop: when did we last refresh the LCD,
     * when did we last ship tags to the ESP32, and a little histogram of
     * how many polls succeeded vs. timed out vs. errored (printed once
     * per uplink interval so we can sanity-check RFID health from the
     * serial terminal). */
    uint32_t last_uplink  = millis();
    uint32_t last_display = millis();
    uint32_t poll_ok = 0, poll_timeout = 0, poll_err = 0;

    while (1) {
        /* Pull one tag frame out of the USART1 ring buffer if one's ready.
         * Non-blocking-ish (has a short internal timeout). */
        yrm100_tag_t tag;
        s = yrm100_poll_inventory(&rfid, &tag);

        if (s == YRM100_OK) {
            poll_ok++;
            /* find_or_add_tag returns 1 only for tags we've never seen —
             * on a new tag we log it and trigger a green "hello!" pulse. */
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
         * tags drop within TAG_TTL_MS + DISPLAY_INTERVAL_MS of leaving range.
         * If num_tags went down after pruning, that means a tag just "left",
         * so we fire a red pulse for that too. */
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
         * and the uplink timer keep ticking while the fade animates. This
         * was a big deal in an earlier version where the pulse was blocking
         * and we kept dropping RFID bytes during the animation. */
        ring_pulse_tick(&ring);

        /* Stats + ESP uplink. The ESP is naturally gated on esp_ready() so
         * back-to-back sends are skipped while Firestore is still flushing
         * the previous batch. Also clamp counters at 255 for printing
         * because dbg_print_u8 only handles unsigned byte. */
        if ((millis() - last_uplink) >= UPLINK_INTERVAL_MS) {
            dbg_puts("[poll] ok=");   dbg_print_u8(poll_ok > 255 ? 255 : poll_ok);
            dbg_puts(" to=");         dbg_print_u8(poll_timeout > 255 ? 255 : poll_timeout);
            dbg_puts(" err=");        dbg_print_u8(poll_err > 255 ? 255 : poll_err);
            dbg_puts(" rxdrop=");     dbg_print_u8(rx_dropped > 255 ? 255 : rx_dropped);
            dbg_puts("\r\n");
            /* Reset the histogram for the next window. */
            poll_ok = poll_timeout = poll_err = 0;
            rx_dropped = 0;

            /* Only actually send if the ESP is idle — no point dropping a
             * new frame into its face while it's still uploading the last one. */
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
