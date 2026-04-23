/* LCD GFX — STM32 port of lib/LCD_GFX.c
 *
 * Algorithms (line/circle/block/char) are kept identical to the AVR
 * reference; only the low-level pin pokes were swapped for the STM32
 * helpers from st7735.h (LCD_cs_*, LCD_dc_*, LCD_wait_idle). */

#include "lcd_gfx.h"
#include "st7735.h"
#include "ASCII_LUT.h"

static void drawPixelInBounds(short x, short y, uint16_t color) {
    if (x >= 0 && x < LCD_WIDTH && y >= 0 && y < LCD_HEIGHT) {
        LCD_drawPixel((uint8_t)x, (uint8_t)y, color);
    }
}

uint16_t rgb565(uint8_t red, uint8_t green, uint8_t blue) {
    return ((((31 * (red   + 4)) / 255) << 11)
          | (((63 * (green + 2)) / 255) <<  5)
          |  ((31 * (blue  + 4)) / 255));
}

void LCD_drawPixel(uint8_t x, uint8_t y, uint16_t color) {
    LCD_setAddr(x, y, x, y);
    SPI_ControllerTx_16bit(color);
}

void LCD_drawChar(uint8_t x, uint8_t y, uint16_t character,
                  uint16_t fColor, uint16_t bColor) {
    uint16_t row = character - 0x20;
    if ((LCD_WIDTH - x > 7) && (LCD_HEIGHT - y > 7)) {
        for (int i = 0; i < 5; i++) {
            uint8_t pixels = (uint8_t)ASCII[row][i];
            for (int j = 0; j < 8; j++) {
                if ((pixels >> j) & 1) {
                    LCD_drawPixel(x + i, y + j, fColor);
                } else {
                    LCD_drawPixel(x + i, y + j, bColor);
                }
            }
        }
    }
}

void LCD_drawCircle(uint8_t x0, uint8_t y0, uint8_t radius, uint16_t color) {
    short x = radius;
    short y = 0;
    short error = 1 - x;

    while (x >= y) {
        drawPixelInBounds(x0 + x, y0 + y, color);
        drawPixelInBounds(x0 + y, y0 + x, color);
        drawPixelInBounds(x0 - y, y0 + x, color);
        drawPixelInBounds(x0 - x, y0 + y, color);
        drawPixelInBounds(x0 - x, y0 - y, color);
        drawPixelInBounds(x0 - y, y0 - x, color);
        drawPixelInBounds(x0 + y, y0 - x, color);
        drawPixelInBounds(x0 + x, y0 - y, color);
        y++;
        if (error < 0) {
            error += 2 * y + 1;
        } else {
            x--;
            error += 2 * (y - x) + 1;
        }
    }
}

void LCD_drawLine(short x0, short y0, short x1, short y1, uint16_t color) {
    int   dx = (x1 > x0) ? (x1 - x0) : (x0 - x1);
    short dy = (y1 > y0) ? (y0 - y1) : (y1 - y0);
    short x_step = (x0 < x1) ? 1 : -1;
    short y_step = (y0 < y1) ? 1 : -1;

    short error = (short)(dx + dy);
    while (1) {
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

void LCD_drawBlock(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1, uint16_t color) {
    if (x0 > x1) { uint8_t t = x0; x0 = x1; x1 = t; }
    if (y0 > y1) { uint8_t t = y0; y0 = y1; y1 = t; }
    if (x1 >= LCD_WIDTH)  x1 = LCD_WIDTH  - 1;
    if (y1 >= LCD_HEIGHT) y1 = LCD_HEIGHT - 1;

    LCD_setAddr(x0, y0, x1, y1);

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

void LCD_setScreen(uint16_t color) {
    LCD_drawBlock(0, 0, LCD_WIDTH - 1, LCD_HEIGHT - 1, color);
}

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
 * scale×scale filled block. Falls back to plain LCD_drawChar for scale<=1. */
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
