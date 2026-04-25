/* ST7735 display driver — STM32F411RE port (see header for pinout)
 *
 * The ST7735 is the controller chip built into our little 1.8" TFT.
 * It has its own framebuffer and a SPI interface that looks like:
 *   - pull CS low to start a transaction
 *   - DC tells it "next byte is a COMMAND" (low) or "DATA" (high)
 *   - clock bytes out on MOSI/SCK
 *   - pull CS high when done
 * We drive SPI1 in master mode at 8 MHz (PCLK/2) and bit-bang the DC
 * and CS lines as plain GPIO. The init sequence in lcd_init() is the
 * vendor's magic cocktail of power / gamma / frame-rate commands that
 * you just have to trust from the datasheet.
 */

#include <stdint.h>
#include "st7735.h"

/* ── Minimal STM32F411RE register map ────────────────────────────
 * Same idea as in main.c — we don't have the HAL, so we declare just
 * enough of the RCC, GPIO, and SPI register layouts to poke directly. */

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

typedef struct {
    volatile uint32_t CR1, CR2, SR, DR, CRCPR, RXCRCR, TXCRCR, I2SCFGR, I2SPR;
} SPI_t;
#define SPI1 ((SPI_t *)0x40013000)

#define SPI_CR1_SPE    (1u << 6)
#define SPI_CR1_MSTR   (1u << 2)
#define SPI_CR1_SSI    (1u << 8)
#define SPI_CR1_SSM    (1u << 9)
#define SPI_SR_TXE     (1u << 1)
#define SPI_SR_BSY     (1u << 7)

/* ── Pin assignments ───────────────────────────────────────────────
 * SCK and MOSI are on GPIOA; DC, RST, CS are on GPIOB. */
#define PIN_SCK   5   /* PA5  */
#define PIN_MOSI  7   /* PA7  */
#define PIN_DC    6   /* PB6  */
#define PIN_RST   15  /* PB15 */
#define PIN_CS    5   /* PB5  */

#define BSRR_SET(pin)   (1u << (pin))
#define BSRR_RESET(pin) (1u << ((pin) + 16))

/* ── Control-line helpers (also used by GFX layer) ───────────────
 * The BSRR register is a "bit set/reset" register — writing to the low
 * half sets a pin, writing to the high half clears it. Using BSRR
 * (instead of read-modify-write on ODR) means these are atomic, so an
 * interrupt can't slice them in half. */

void LCD_cs_low(void)  { GPIOB->BSRR = BSRR_RESET(PIN_CS); }
void LCD_cs_high(void) { GPIOB->BSRR = BSRR_SET(PIN_CS);   }
void LCD_dc_cmd(void)  { GPIOB->BSRR = BSRR_RESET(PIN_DC); }
void LCD_dc_data(void) { GPIOB->BSRR = BSRR_SET(PIN_DC);   }

/* Reset pin (active low). Only used during lcd_init(). */
static void rst_low(void)  { GPIOB->BSRR = BSRR_RESET(PIN_RST); }
static void rst_high(void) { GPIOB->BSRR = BSRR_SET(PIN_RST);   }

/* Spin until the SPI has finished shifting out the last byte. First
 * wait ensures the byte has moved from DR into the shifter (TXE), then
 * the second waits for BSY to drop, meaning the line has actually
 * returned to idle. If we lift CS too early the display sees a half
 * byte and gets confused. */
void LCD_wait_idle(void) {
    while (!(SPI1->SR & SPI_SR_TXE));
    while (SPI1->SR & SPI_SR_BSY);
}

/* ── Timing ─────────────────────────────────────────────────────
 * Busy-wait calibrated for HSI @ 16 MHz. Inner loop is ~4 cycles
 * (nop + counter update + branch), so 4000 iters ≈ 1 ms. Good
 * enough for display init delays; ±10% is fine here.
 */
void Delay_ms(unsigned int n) {
    for (unsigned int i = 0; i < n; i++) {
        for (volatile uint32_t c = 0; c < 4000; c++) {
            __asm__ volatile("nop");
        }
    }
}

/* ── SPI primitives ──────────────────────────────────────────────
 * Two flavours of each helper: "_stream" variants assume CS is already
 * low and don't mess with it (cheap inner-loop calls for bulk pixel
 * writes), while the non-stream versions bookend with CS low/high so
 * they work for one-off pokes. */

/* Push one byte into the SPI TX register. The cast to volatile uint8_t*
 * is deliberate — writing DR as a full 32-bit word would put the SPI
 * into 16-bit mode and everything gets misaligned. */
void SPI_ControllerTx_stream(uint8_t stream) {
    while (!(SPI1->SR & SPI_SR_TXE));
    *((volatile uint8_t *)&SPI1->DR) = stream;
}

void SPI_ControllerTx(uint8_t data) {
    LCD_cs_low();
    SPI_ControllerTx_stream(data);
    LCD_wait_idle();
    LCD_cs_high();
}

/* Two-byte send is what we use for pixel colors (RGB565 = 16 bits).
 * MSB first so the display interprets the byte order correctly. */
void SPI_ControllerTx_16bit_stream(uint16_t data) {
    SPI_ControllerTx_stream((uint8_t)(data >> 8));
    SPI_ControllerTx_stream((uint8_t)data);
}

void SPI_ControllerTx_16bit(uint16_t data) {
    LCD_cs_low();
    SPI_ControllerTx_16bit_stream(data);
    LCD_wait_idle();
    LCD_cs_high();
}

/* ── Init ────────────────────────────────────────────────────────
 * Two-part: first lcd_pin_init() gets the GPIOs and RST/CS/DC all set
 * up, then SPI_Controller_Init() configures the SPI1 peripheral, and
 * finally lcd_init() runs the vendor's panel init sequence. */

static void lcd_pin_init(void) {
    /* Turn on the clocks we need. Even though main.c also enables these
     * we do it again here to keep the driver self-contained. */
    RCC->AHB1ENR |= (1u << 0) | (1u << 1);
    RCC->APB2ENR |= (1u << 12);

    /* PA5 = SCK, PA7 = MOSI — both AF5 on SPI1 */
    GPIOA->MODER &= ~((3u << (PIN_SCK * 2)) | (3u << (PIN_MOSI * 2)));
    GPIOA->MODER |=  ((2u << (PIN_SCK * 2)) | (2u << (PIN_MOSI * 2)));
    GPIOA->AFR[0] &= ~((0xFu << (PIN_SCK * 4)) | (0xFu << (PIN_MOSI * 4)));
    GPIOA->AFR[0] |=  ((5u   << (PIN_SCK * 4)) | (5u   << (PIN_MOSI * 4)));
    GPIOA->OSPEEDR |= (3u << (PIN_SCK * 2)) | (3u << (PIN_MOSI * 2));

    /* PB5 = CS, PB6 = DC, PB15 = RST — push-pull outputs */
    GPIOB->MODER &= ~((3u << (PIN_DC * 2))
                    | (3u << (PIN_RST * 2))
                    | (3u << (PIN_CS * 2)));
    GPIOB->MODER |=  ((1u << (PIN_DC * 2))
                    | (1u << (PIN_RST * 2))
                    | (1u << (PIN_CS * 2)));
    GPIOB->OSPEEDR |= (3u << (PIN_DC * 2))
                    | (3u << (PIN_RST * 2))
                    | (3u << (PIN_CS * 2));

    /* Idle state before we start talking: CS high (chip deselected),
     * DC high (data mode is the default), then do a proper hardware reset
     * by pulsing RST low for 50 ms and waiting another 50 ms for the
     * controller to wake back up. The datasheet demands >=10 µs low and
     * >=120 ms wait time — 50+50 is safely over that. */
    LCD_cs_high();
    LCD_dc_data();
    rst_low();
    Delay_ms(50);
    rst_high();
    Delay_ms(50);
}

/* Configure the SPI1 peripheral. The ST7735 is cool with Mode 0
 * (CPOL=0 CPHA=0) which is the default anyway. We enable software slave
 * management (SSM+SSI) so the SPI hardware treats NSS as "always
 * present" and we can wave our own CS pin (PB5) by hand. SPE at the
 * end turns the whole thing on — any config changes after SPE is set
 * require disabling first, so we batch everything. */
static void SPI_Controller_Init(void) {
    SPI1->CR2 = 0;
    SPI1->CR1 = SPI_CR1_SSM
              | SPI_CR1_SSI
              | SPI_CR1_MSTR;           /* BR[2:0] = 000 → fPCLK/2 */
    SPI1->CR1 |= SPI_CR1_SPE;
}

/* The big one: get the display from "just powered up" to "actually
 * drawing pixels". After the hardware reset in lcd_pin_init we walk
 * through a long init sequence — wake up from sleep, set the frame
 * rate, program the gamma curves, pick 16-bit color mode, and flip
 * the display on. Each row in the table below is one command plus its
 * parameter bytes, plus a "wait this many ms afterwards" value. */
void lcd_init(void) {
    lcd_pin_init();
    SPI_Controller_Init();
    Delay_ms(5);

    /* Init sequence copied verbatim from the AVR reference
     * (lib/ST7735.c:143). Format: {cmd, num_data, [data...], wait_ms}. */
    static const uint8_t ST7735_cmds[] = {
        ST7735_SWRESET, 0, 150,
        ST7735_SLPOUT,  0, 255,
        ST7735_FRMCTR1, 3, 0x01, 0x2C, 0x2D, 0,
        ST7735_FRMCTR2, 3, 0x01, 0x2C, 0x2D, 0,
        ST7735_FRMCTR3, 6, 0x01, 0x2C, 0x2D, 0x01, 0x2C, 0x2D, 0,
        ST7735_INVCTR,  1, 0x07, 0,
        ST7735_PWCTR1,  3, 0xA2, 0x02, 0x84, 5,
        ST7735_PWCTR2,  1, 0xC5, 5,
        ST7735_PWCTR3,  2, 0x0A, 0x00, 5,
        ST7735_PWCTR4,  2, 0x8A, 0x2A, 5,
        ST7735_PWCTR5,  2, 0x8A, 0xEE, 5,
        ST7735_VMCTR1,  1, 0x0E, 0,
        ST7735_INVOFF,  0, 0,
        ST7735_MADCTL,  1, 0xC8, 0,
        ST7735_COLMOD,  1, 0x05, 0,
        ST7735_CASET,   4, 0x00, 0x00, 0x00, 0x7F, 0,
        ST7735_RASET,   4, 0x00, 0x00, 0x00, 0x9F, 0,
        ST7735_GMCTRP1, 16, 0x02, 0x1C, 0x07, 0x12, 0x37, 0x32, 0x29, 0x2D,
                            0x29, 0x25, 0x2B, 0x39, 0x00, 0x01, 0x03, 0x10, 0,
        ST7735_GMCTRN1, 16, 0x03, 0x1D, 0x07, 0x06, 0x2E, 0x2C, 0x29, 0x2D,
                            0x2E, 0x2E, 0x37, 0x3F, 0x00, 0x00, 0x02, 0x10, 0,
        ST7735_NORON,   0, 10,
        ST7735_DISPON,  0, 100,
        ST7735_MADCTL,  1, MADCTL_MX | MADCTL_MV | MADCTL_RGB, 10
    };
    sendCommands(ST7735_cmds, 22);
}

/* Walk through a compacted command table ({cmd, n, data..., delay_ms})
 * and fire each entry at the display. CS stays low for the whole batch
 * and we toggle DC around each cmd/data split. This is the same idea
 * as in the Adafruit / Ada Uno reference drivers — a little interpreter
 * that makes the init table above readable. */
void sendCommands(const uint8_t *cmds, uint8_t length) {
    uint8_t numCommands = length;
    uint8_t numData, waitTime;

    LCD_cs_low();
    while (numCommands--) {
        LCD_dc_cmd();
        SPI_ControllerTx_stream(*cmds++);
        numData = *cmds++;
        /* Need to wait until command byte is fully clocked before raising DC,
         * otherwise the display would read the command byte as data. */
        LCD_wait_idle();
        LCD_dc_data();
        while (numData--) {
            SPI_ControllerTx_stream(*cmds++);
        }
        LCD_wait_idle();
        waitTime = *cmds++;
        if (waitTime != 0) {
            /* 255 is a sentinel meaning "500 ms please" so the longest
             * delays still fit in a byte. */
            Delay_ms((waitTime == 255) ? 500 : waitTime);
        }
    }
    LCD_cs_high();
}

/* Tell the display "the next RAMWR data dump goes to the rectangle from
 * (x0,y0) to (x1,y1), inclusive". We issue CASET for the column range,
 * RASET for the row range, then RAMWR which opens the write cursor. */
void LCD_setAddr(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1) {
    uint8_t cmds[] = {
        ST7735_CASET, 4, 0x00, x0, 0x00, x1, 0,
        ST7735_RASET, 4, 0x00, y0, 0x00, y1, 0,
        ST7735_RAMWR, 0, 0
    };
    sendCommands(cmds, 3);
}

/* Rotate the frame. The MADCTL register flips axes and swaps X/Y, so we
 * just build the right bit-pattern per rotation case. We ended up on
 * rotation 1 (landscape 160×128) during lcd_init, but this is here in
 * case a future layout wants something else. */
void LCD_rotate(uint8_t r) {
    uint8_t madctl;
    switch (r % 4) {
        case 0:  madctl = MADCTL_MX | MADCTL_MY | MADCTL_RGB; break;
        case 1:  madctl = MADCTL_MY | MADCTL_MV | MADCTL_RGB; break;
        case 2:  madctl = MADCTL_RGB;                         break;
        case 3:  madctl = MADCTL_MX | MADCTL_MV | MADCTL_RGB; break;
        default: madctl = MADCTL_MX | MADCTL_MY | MADCTL_RGB; break;
    }
    uint8_t cmds[] = { ST7735_MADCTL, 1, madctl, 0 };
    sendCommands(cmds, 1);
}
