#ifndef NEOPIXEL_H
#define NEOPIXEL_H

#include <stdint.h>
#include <stddef.h>

/* ── Ring geometry ─────────────────────────────────────────────────
 * Fixed for the 12-LED NeoPixel ring. WS2812B-style, single-wire,
 * 800 kHz, 24 bits per pixel in GRB order.
 */
#define NEOPIXEL_NUM_LEDS        12
#define NEOPIXEL_BYTES_PER_PIXEL 3
#define NEOPIXEL_BUFFER_SIZE     (NEOPIXEL_NUM_LEDS * NEOPIXEL_BYTES_PER_PIXEL)

/* ── MCU clock ──────────────────────────────────────────────────────
 * Timing tables in neopixel.c are derived from this. The project runs
 * HSI @ 16 MHz (see clock_init in main.c). If you change clocks, keep
 * this in sync or the waveform will be wrong.
 */
#ifndef NEOPIXEL_F_CPU
#define NEOPIXEL_F_CPU 16000000UL
#endif

/* ── GPIO register layout (STM32F4xx) ────────────────────────────── */
typedef struct {
    volatile uint32_t MODER, OTYPER, OSPEEDR, PUPDR, IDR, ODR, BSRR, LCKR;
    volatile uint32_t AFR[2];
} neopixel_gpio_t;

/* ── Handle ────────────────────────────────────────────────────────
 * `pixels` holds the wire-order byte stream (GRB). Brightness is 0-255
 * where 255 = full (no scaling) and is applied when set_pixel_* writes
 * into the buffer.
 */
typedef struct {
    neopixel_gpio_t *port;
    uint8_t pin;
    uint8_t brightness;
    uint8_t pixels[NEOPIXEL_BUFFER_SIZE];
} neopixel_t;

/* ── Color helpers ─────────────────────────────────────────────────
 * Packed 0x00RRGGBB, identical to Adafruit_NeoPixel::Color().
 */
#define NEOPIXEL_COLOR(r, g, b) \
    (((uint32_t)(uint8_t)(r) << 16) | \
     ((uint32_t)(uint8_t)(g) <<  8) | \
      (uint32_t)(uint8_t)(b))

/* ── Lifecycle ─────────────────────────────────────────────────────
 * Configures `pin` on `port` as push-pull output, very-high speed,
 * drives it low, clears the pixel buffer, and sets brightness = 255.
 * Caller must have enabled the GPIO port clock in RCC->AHB1ENR.
 */
void neopixel_init(neopixel_t *np, neopixel_gpio_t *port, uint8_t pin);

/* ── Buffer mutation ──────────────────────────────────────────────
 * These only touch RAM; call neopixel_show() to push the buffer to
 * the ring. Out-of-range indices are silently ignored.
 */
void neopixel_set_pixel_rgb(neopixel_t *np, uint16_t n,
                            uint8_t r, uint8_t g, uint8_t b);
void neopixel_set_pixel_color(neopixel_t *np, uint16_t n, uint32_t color);
void neopixel_fill(neopixel_t *np, uint32_t color);
void neopixel_clear(neopixel_t *np);
void neopixel_set_brightness(neopixel_t *np, uint8_t brightness);

/* ── Transmit ──────────────────────────────────────────────────────
 * Bit-bangs the 24*N-bit frame out `pin` with interrupts disabled and
 * SysTick reconfigured for 800 kHz. The 1 ms tick handler may miss a
 * single increment during the ~360 µs transfer (plus 50 µs latch).
 */
void neopixel_show(neopixel_t *np);

/* ── Extras ────────────────────────────────────────────────────────
 * HSV → packed RGB (hue 0-65535, sat/val 0-255). Gamma-correction
 * table from the Adafruit reference, 2.6 exponent.
 */
uint32_t neopixel_color_hsv(uint16_t hue, uint8_t sat, uint8_t val);
uint8_t  neopixel_gamma8(uint8_t x);

#endif /* NEOPIXEL_H */
