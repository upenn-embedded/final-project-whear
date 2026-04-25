/* NeoPixel (WS2812B) driver — single-wire, 800 kHz, bare-metal STM32F4.
 *
 * Uses cycle-counted inline assembly for bit timing so the waveform is
 * deterministic on a 16 MHz HSI clock. Interrupts are disabled during
 * the ~360 µs transfer.
 *
 * Quick refresher on how NeoPixels work: each LED is actually a chained
 * shift register + three PWM channels (R/G/B). You send 24 bits per LED
 * in GRB order over a single data wire. The trick is that there's no
 * clock line — the chip distinguishes 0 from 1 by the width of the HIGH
 * pulse within a fixed ~1.25 µs window. At 16 MHz that gives us only
 * 20 CPU cycles per bit, which is why this is written in asm — there's
 * literally not enough time for a C loop to do the bookkeeping.
 */

#include "neopixel.h"

/* Adafruit gamma table (exponent 2.6). */
static const uint8_t neopixel_gamma_table[256] = {
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   2,   2,   2,   2,   2,   2,   2,   2,   3,
    3,   3,   3,   3,   3,   4,   4,   4,   4,   5,   5,   5,   5,   5,   6,
    6,   6,   6,   7,   7,   7,   8,   8,   8,   9,   9,   9,   10,  10,  10,
    11,  11,  11,  12,  12,  13,  13,  13,  14,  14,  15,  15,  16,  16,  17,
    17,  18,  18,  19,  19,  20,  20,  21,  21,  22,  22,  23,  24,  24,  25,
    25,  26,  27,  27,  28,  29,  29,  30,  31,  31,  32,  33,  34,  34,  35,
    36,  37,  38,  38,  39,  40,  41,  42,  42,  43,  44,  45,  46,  47,  48,
    49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,  60,  61,  62,  63,
    64,  65,  66,  68,  69,  70,  71,  72,  73,  75,  76,  77,  78,  80,  81,
    82,  84,  85,  86,  88,  89,  90,  92,  93,  94,  96,  97,  99,  100, 102,
    103, 105, 106, 108, 109, 111, 112, 114, 115, 117, 119, 120, 122, 124, 125,
    127, 129, 130, 132, 134, 136, 137, 139, 141, 143, 145, 146, 148, 150, 152,
    154, 156, 158, 160, 162, 164, 166, 168, 170, 172, 174, 176, 178, 180, 182,
    184, 186, 188, 191, 193, 195, 197, 199, 202, 204, 206, 209, 211, 213, 215,
    218, 220, 223, 225, 227, 230, 232, 235, 237, 240, 242, 245, 247, 250, 252,
    255
};

/* Set up the GPIO pin that drives the LED string. We need it to be a
 * fast push-pull output because the 800 kHz waveform has 300 ns rise
 * times — a lazy output driver would smooth those edges into nothing. */
void neopixel_init(neopixel_t *np, neopixel_gpio_t *port, uint8_t pin) {
    np->port = port;
    np->pin = pin;
    np->brightness = 255;

    /* Wipe the framebuffer so a fresh show() draws nothing, not garbage. */
    for (uint16_t i = 0; i < NEOPIXEL_BUFFER_SIZE; i++) {
        np->pixels[i] = 0;
    }

    /* Pin config: general-purpose output (MODER=01), push-pull (OTYPER=0),
     * max slew rate (OSPEEDR=11), no pull resistor (PUPDR=00). */
    port->MODER   &= ~(3u << (pin * 2));
    port->MODER   |=  (1u << (pin * 2));
    port->OTYPER  &= ~(1u << pin);
    port->OSPEEDR |=  (3u << (pin * 2));
    port->PUPDR   &= ~(3u << (pin * 2));

    /* Drive the line LOW now so the very first bit we send has a clean
     * 0→1 rising edge (WS2812B latches on rising edges). Writing to BSRR
     * bits 16..31 resets the matching output bit atomically. */
    port->BSRR = (1u << (pin + 16));
}

/* Copy one pixel's R/G/B into the framebuffer, scaling for brightness
 * on the way. The WS2812B chain expects GRB order, NOT RGB, which is a
 * classic foot-gun — the colors look swapped if you forget. */
static inline void neopixel_store(uint8_t *dst, uint8_t r, uint8_t g, uint8_t b,
                                  uint8_t brightness) {
    if (brightness < 255) {
        /* Brightness is 0..255; treat 255 as "100%, no scaling" so we
         * don't lose one bit of resolution for no reason. The +1 makes
         * the math round to nearest without a divide. */
        uint16_t s = (uint16_t)brightness + 1;
        r = (uint8_t)(((uint16_t)r * s) >> 8);
        g = (uint8_t)(((uint16_t)g * s) >> 8);
        b = (uint8_t)(((uint16_t)b * s) >> 8);
    }
    dst[0] = g;
    dst[1] = r;
    dst[2] = b;
}

/* Public API: set LED n's color from separate R/G/B bytes. Silently
 * ignores out-of-range indices so callers don't have to bounds-check. */
void neopixel_set_pixel_rgb(neopixel_t *np, uint16_t n,
                            uint8_t r, uint8_t g, uint8_t b) {
    if (n >= NEOPIXEL_NUM_LEDS) return;
    neopixel_store(&np->pixels[n * NEOPIXEL_BYTES_PER_PIXEL],
                   r, g, b, np->brightness);
}

/* Same thing but takes a packed 0x00RRGGBB integer. Just unpacks and
 * forwards — easier for callers that already have colors as constants. */
void neopixel_set_pixel_color(neopixel_t *np, uint16_t n, uint32_t color) {
    neopixel_set_pixel_rgb(np, n,
                           (uint8_t)(color >> 16),
                           (uint8_t)(color >> 8),
                           (uint8_t)(color));
}

/* Paint every LED the same color. Used for the ring pulse animations. */
void neopixel_fill(neopixel_t *np, uint32_t color) {
    for (uint16_t i = 0; i < NEOPIXEL_NUM_LEDS; i++) {
        neopixel_set_pixel_color(np, i, color);
    }
}

/* Fast "all off" that skips the brightness math — just zeroes the buffer. */
void neopixel_clear(neopixel_t *np) {
    for (uint16_t i = 0; i < NEOPIXEL_BUFFER_SIZE; i++) {
        np->pixels[i] = 0;
    }
}

/* Store the brightness scale that the next set_pixel call will apply.
 * Changing this doesn't retroactively rescale what's already in the
 * buffer — you'd have to re-paint to see the effect. */
void neopixel_set_brightness(neopixel_t *np, uint8_t brightness) {
    np->brightness = brightness;
}

/* Cycle-counted inline-asm bit-bang for 16 MHz HSI. Each bit is a 20-cycle
 * period (1.25 µs); NOP padding makes every bit identical so there's no
 * jitter from the compiler's choice of shifts/branches. Targets:
 *   T0H ≈ 5 cycles  ≈ 312 ns  (WS2812B spec: 250-550)
 *   T1H ≈ 12 cycles ≈ 750 ns  (WS2812B spec: 650-950)
 * The SysTick approach from Adafruit's reference can't hit these at 16 MHz
 * because the while(VAL>cyc) loop is ~4 cycles per iteration, which lets
 * T0H overshoot into T1H range — every 0-bit gets read as a 1-bit, so the
 * ring lights up white regardless of the buffer contents. */
void neopixel_show(neopixel_t *np) {
    uint8_t *p   = np->pixels;
    uint8_t *end = p + NEOPIXEL_BUFFER_SIZE;
    const uint32_t bsrr_set = 1u << np->pin;
    const uint32_t bsrr_rst = 1u << (np->pin + 16);
    volatile uint32_t *bsrr = &np->port->BSRR;
    uint32_t byte_r, mask_r;

    __asm volatile ("cpsid i" ::: "memory");

    __asm volatile (
        "0: ldrb  %[b], [%[p]], #1      \n\t"
        "   movs  %[m], #0x80           \n\t"
        "1: str   %[s], [%[br]]         \n\t"  /* HIGH                C0  */
        "   tst   %[b], %[m]            \n\t"  /*                     C1  */
        "   nop                         \n\t"  /*                     C2  */
        "   nop                         \n\t"  /*                     C3  */
        "   nop                         \n\t"  /*                     C4  */
        "   it    eq                    \n\t"
        "   streq %[l], [%[br]]         \n\t"  /* bit=0 -> LOW        C5  */
        "   nop                         \n\t"  /*                     C6  */
        "   nop                         \n\t"  /*                     C7  */
        "   nop                         \n\t"  /*                     C8  */
        "   nop                         \n\t"  /*                     C9  */
        "   nop                         \n\t"  /*                     C10 */
        "   nop                         \n\t"  /*                     C11 */
        "   str   %[l], [%[br]]         \n\t"  /* LOW (redundant @ 0) C12 */
        "   nop                         \n\t"  /*                     C13 */
        "   nop                         \n\t"  /*                     C14 */
        "   nop                         \n\t"  /*                     C15 */
        "   nop                         \n\t"  /*                     C16 */
        "   nop                         \n\t"  /*                     C17 */
        "   lsrs  %[m], %[m], #1        \n\t"  /*                     C18 */
        "   bne   1b                    \n\t"  /* taken = 2 cyc -> C19-20 */
        "   cmp   %[p], %[e]            \n\t"
        "   bcc   0b                    \n\t"
        : [p] "+r" (p), [b] "=&r" (byte_r), [m] "=&r" (mask_r)
        : [s] "r" (bsrr_set), [l] "r" (bsrr_rst),
          [br] "r" (bsrr), [e] "r" (end)
        : "cc", "memory"
    );

    __asm volatile ("cpsie i" ::: "memory");

    /* ≥50 µs low to latch. ~1000 iterations of a volatile-counter loop
     * is ~560 µs at 16 MHz, plenty of margin. */
    for (volatile uint32_t d = 0; d < 1000; d++) {
        __asm volatile ("nop");
    }
}

/* HSV → packed RGB conversion. HSV is a much friendlier color model
 * for animation math ("slide the hue while keeping saturation & value
 * constant") than raw RGB, where a smooth rainbow requires six if-else
 * branches. Inputs match Adafruit's NeoPixel library so external code
 * that assumes that format still works. */
uint32_t neopixel_color_hsv(uint16_t hue, uint8_t sat, uint8_t val) {
    uint8_t r, g, b;

    /* Remap 16-bit hue to 0..1529 (six 255-wide sectors). */
    hue = (uint16_t)(((uint32_t)hue * 1530UL + 32768UL) / 65536UL);

    if (hue < 510) {
        b = 0;
        if (hue < 255) { r = 255;            g = (uint8_t)hue;        }
        else           { r = (uint8_t)(510 - hue); g = 255;            }
    } else if (hue < 1020) {
        r = 0;
        if (hue < 765) { g = 255;            b = (uint8_t)(hue - 510); }
        else           { g = (uint8_t)(1020 - hue); b = 255;           }
    } else if (hue < 1530) {
        g = 0;
        if (hue < 1275) { r = (uint8_t)(hue - 1020); b = 255;          }
        else            { r = 255;           b = (uint8_t)(1530 - hue);}
    } else {
        r = 255; g = 0; b = 0;
    }

    uint16_t s1 = (uint16_t)sat + 1;
    uint8_t  s2 = (uint8_t)(255 - sat);
    uint16_t v1 = (uint16_t)val + 1;

    r = (uint8_t)(((((uint16_t)r * s1) >> 8) + s2) * v1 >> 8);
    g = (uint8_t)(((((uint16_t)g * s1) >> 8) + s2) * v1 >> 8);
    b = (uint8_t)(((((uint16_t)b * s1) >> 8) + s2) * v1 >> 8);

    return ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

/* LEDs are linear-in-current but our eyes are logarithmic. Apply this
 * gamma correction to an 8-bit channel so a fade from 0 to 255 looks
 * visually smooth instead of "nothing...nothing...BRIGHT AS THE SUN". */
uint8_t neopixel_gamma8(uint8_t x) {
    return neopixel_gamma_table[x];
}
