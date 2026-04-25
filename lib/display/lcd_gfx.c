/* LCD GFX — STM32 port of lib/LCD_GFX.c
 *
 * This is the "graphics primitives" layer that sits on top of the bare
 * st7735 SPI driver. It gives us pixels, lines, rectangles, circles,
 * and text. The algorithms (Bresenham line, midpoint circle, 5×8 bitmap
 * font) are all stock textbook stuff — I just plugged the pixel-write
 * backend into our STM32 SPI helpers instead of the AVR ones.
 *
 * Algorithms (line/circle/block/char) are kept identical to the AVR
 * reference; only the low-level pin pokes were swapped for the STM32
 * helpers from st7735.h (LCD_cs_*, LCD_dc_*, LCD_wait_idle). */

#include "lcd_gfx.h"
#include "st7735.h"
#include "ASCII_LUT.h"

/* Safe drawPixel that silently drops pixels outside the screen. Used
 * by the circle algorithm, which naturally wants to plot points that
 * can fall off the edge. Signed shorts so negative arithmetic doesn't
 * wrap around to a huge uint8 value. */
static void drawPixelInBounds(short x, short y, uint16_t color) {
    if (x >= 0 && x < LCD_WIDTH && y >= 0 && y < LCD_HEIGHT) {
        LCD_drawPixel((uint8_t)x, (uint8_t)y, color);
    }
}

/* Pack an 8-8-8 RGB triplet into the 5-6-5 format the display uses
 * internally. The +4/+2 and /255 are a rounding trick so that full
 * 0xFF maps cleanly to the max of each field (31/63/31) without bias. */
uint16_t rgb565(uint8_t red, uint8_t green, uint8_t blue) {
    return ((((31 * (red   + 4)) / 255) << 11)
          | (((63 * (green + 2)) / 255) <<  5)
          |  ((31 * (blue  + 4)) / 255));
}

/* The most fundamental primitive: set one pixel. Everything else
 * ultimately boils down to calling this in a loop. It's slow-ish
 * (one SPI transaction per pixel) but fine for character rendering. */
void LCD_drawPixel(uint8_t x, uint8_t y, uint16_t color) {
    LCD_setAddr(x, y, x, y);
    SPI_ControllerTx_16bit(color);
}

/* Draw one ASCII character. Our font in ASCII_LUT.h is the classic
 * 5×8 bitmap (5 pixel columns × 8 pixel rows per glyph). Each column
 * is stored as a single byte where bit 0 is the top pixel and bit 7 is
 * the bottom. We subtract 0x20 because the font table starts at space. */
void LCD_drawChar(uint8_t x, uint8_t y, uint16_t character,
                  uint16_t fColor, uint16_t bColor) {
    uint16_t row = character - 0x20;
    /* Bounds check so we don't try to draw a glyph that spills past
     * the screen edge. */
    if ((LCD_WIDTH - x > 7) && (LCD_HEIGHT - y > 7)) {
        for (int i = 0; i < 5; i++) {
            uint8_t pixels = (uint8_t)ASCII[row][i];
            for (int j = 0; j < 8; j++) {
                /* Test the j-th bit to decide foreground vs background. */
                if ((pixels >> j) & 1) {
                    LCD_drawPixel(x + i, y + j, fColor);
                } else {
                    LCD_drawPixel(x + i, y + j, bColor);
                }
            }
        }
    }
}

/* Midpoint circle algorithm. We compute pixels along only a 45°
 * slice (x>=y) and mirror them to the other 7 octants. That's 8× less
 * math and it keeps the circle nicely symmetric. The `error` term is
 * an integer version of "how far is this pixel from the true circle". */
void LCD_drawCircle(uint8_t x0, uint8_t y0, uint8_t radius, uint16_t color) {
    short x = radius;
    short y = 0;
    short error = 1 - x;

    while (x >= y) {
        /* One pixel per octant = 8 mirrored pixels per iteration. */
        drawPixelInBounds(x0 + x, y0 + y, color);
        drawPixelInBounds(x0 + y, y0 + x, color);
        drawPixelInBounds(x0 - y, y0 + x, color);
        drawPixelInBounds(x0 - x, y0 + y, color);
        drawPixelInBounds(x0 - x, y0 - y, color);
        drawPixelInBounds(x0 - y, y0 - x, color);
        drawPixelInBounds(x0 + y, y0 - x, color);
        drawPixelInBounds(x0 + x, y0 - y, color);
        y++;
        /* Decide whether to also step x inward or not — classic
         * Bresenham-style error update. */
        if (error < 0) {
            error += 2 * y + 1;
        } else {
            x--;
            error += 2 * (y - x) + 1;
        }
    }
}

/* Bresenham's line algorithm (integer-only, works for any slope and
 * any direction). The `error` accumulator tracks how far we've drifted
 * off the ideal line, and each step we step in X and/or Y depending on
 * whether doing so takes us closer to the true line. */
void LCD_drawLine(short x0, short y0, short x1, short y1, uint16_t color) {
    int   dx = (x1 > x0) ? (x1 - x0) : (x0 - x1);
    short dy = (y1 > y0) ? (y0 - y1) : (y1 - y0);
    short x_step = (x0 < x1) ? 1 : -1;
    short y_step = (y0 < y1) ? 1 : -1;

    short error = (short)(dx + dy);
    while (1) {
        /* Clip to screen before drawing. */
        if (x0 >= 0 && x0 < LCD_WIDTH && y0 >= 0 && y0 < LCD_HEIGHT) {
            LCD_drawPixel((uint8_t)x0, (uint8_t)y0, color);
        }
        if (x0 == x1 && y0 == y1) break;

        short tmp = error;
        if (error * 2 >= dy) { tmp += dy; x0 += x_step; }
        if (error * 2 <= dx) { tmp += (short)dx; y0 += y_step; }
        error = tmp;
    }
}

/* Fill a solid rectangle. This is a big speedup over naive pixel-by-pixel
 * because we set the address window once and then stream pixels as one
 * long SPI burst without toggling CS every time. Used heavily by
 * display_update() in main.c to wipe regions before repainting. */
void LCD_drawBlock(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1, uint16_t color) {
    /* Swap coords if the caller passed them inverted. */
    if (x0 > x1) { uint8_t t = x0; x0 = x1; x1 = t; }
    if (y0 > y1) { uint8_t t = y0; y0 = y1; y1 = t; }
    /* Clip to screen. */
    if (x1 >= LCD_WIDTH)  x1 = LCD_WIDTH  - 1;
    if (y1 >= LCD_HEIGHT) y1 = LCD_HEIGHT - 1;

    LCD_setAddr(x0, y0, x1, y1);

    /* One big SPI burst. We keep CS low for the whole thing so the
     * display sees continuous data as it auto-increments its internal
     * write cursor across the address window. */
    LCD_dc_data();
    LCD_cs_low();
    for (int i = 0; i < (x1 - x0 + 1); i++) {
        for (int j = 0; j < (y1 - y0 + 1); j++) {
            SPI_ControllerTx_16bit_stream(color);
        }
    }
    LCD_wait_idle();
    LCD_cs_high();
}

/* Trivial helper: fill the whole screen. */
void LCD_setScreen(uint16_t color) {
    LCD_drawBlock(0, 0, LCD_WIDTH - 1, LCD_HEIGHT - 1, color);
}

/* Render a null-terminated C string starting at (x, y). Each glyph
 * is 5 pixels wide + 1 pixel of inter-character spacing = 6 pixels
 * per character. '\n' wraps to the next row and resets x to 0. */
void LCD_drawString(uint8_t x, uint8_t y, const char *str, uint16_t fg, uint16_t bg) {
    while (*str != '\0') {
        if (*str == '\n') {
            y += 8;
            x = 0;
        } else {
            LCD_drawChar(x, y, (uint8_t)*str, fg, bg);
            x += 6;
        }
        str++;
    }
}

/* Draw a glyph at an integer pixel-scale. Each source pixel becomes a
 * scale×scale filled block. Falls back to plain LCD_drawChar for scale<=1.
 *
 * This is what lets us draw the giant "24" on the front screen — it's
 * the regular 5×8 font, just blown up with nearest-neighbor scaling. */
void LCD_drawCharScaled(uint8_t x, uint8_t y, uint16_t character,
                        uint16_t fColor, uint16_t bColor, uint8_t scale) {
    if (scale <= 1) {
        LCD_drawChar(x, y, character, fColor, bColor);
        return;
    }
    uint16_t row = character - 0x20;
    if ((uint16_t)x + 5u * scale > LCD_WIDTH) return;
    if ((uint16_t)y + 8u * scale > LCD_HEIGHT) return;
    for (uint8_t i = 0; i < 5; i++) {
        uint8_t pixels = (uint8_t)ASCII[row][i];
        for (uint8_t j = 0; j < 8; j++) {
            uint16_t c = ((pixels >> j) & 1) ? fColor : bColor;
            uint8_t x0 = (uint8_t)(x + i * scale);
            uint8_t y0 = (uint8_t)(y + j * scale);
            LCD_drawBlock(x0, y0,
                          (uint8_t)(x0 + scale - 1),
                          (uint8_t)(y0 + scale - 1), c);
        }
    }
}

void LCD_drawStringScaled(uint8_t x, uint8_t y, const char *str,
                          uint16_t fg, uint16_t bg, uint8_t scale) {
    if (scale == 0) scale = 1;
    uint8_t step = (uint8_t)(6 * scale);
    while (*str != '\0') {
        if (*str == '\n') {
            y = (uint8_t)(y + 8 * scale);
            x = 0;
        } else {
            LCD_drawCharScaled(x, y, (uint8_t)*str, fg, bg, scale);
            x = (uint8_t)(x + step);
        }
        str++;
    }
}
