/* LCD GFX — STM32 port of lib/LCD_GFX.h
 *
 * Graphics primitives on top of the st7735 SPI driver. This header is
 * what main.c actually includes to draw to the screen — pixels, blocks,
 * circles, lines, strings with optional integer scaling.
 *
 * Same API as the AVR reference; ASCII font table is pulled in by the .c. */

#ifndef LCD_GFX_STM32_H_
#define LCD_GFX_STM32_H_

#include <stdint.h>

/* Preset colors in RGB565 format (5 bits red, 6 green, 5 blue). These
 * were hand-computed once so we don't call rgb565() at runtime for the
 * common ones. */
#define BLACK   0x0000
#define WHITE   0xFFFF
#define BLUE    0x001F
#define RED     0xF800
#define GREEN   0x07E0
#define CYAN    0x07FF
#define MAGENTA 0xF81F
#define YELLOW  0xFFE0

uint16_t rgb565(uint8_t red, uint8_t green, uint8_t blue);
void LCD_drawPixel(uint8_t x, uint8_t y, uint16_t color);
void LCD_drawChar(uint8_t x, uint8_t y, uint16_t character, uint16_t fColor, uint16_t bColor);
void LCD_drawCircle(uint8_t x0, uint8_t y0, uint8_t radius, uint16_t color);
void LCD_drawLine(short x0, short y0, short x1, short y1, uint16_t c);
void LCD_drawBlock(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1, uint16_t color);
void LCD_setScreen(uint16_t color);
void LCD_drawString(uint8_t x, uint8_t y, const char *str, uint16_t fg, uint16_t bg);
void LCD_drawCharScaled(uint8_t x, uint8_t y, uint16_t character,
                        uint16_t fColor, uint16_t bColor, uint8_t scale);
void LCD_drawStringScaled(uint8_t x, uint8_t y, const char *str,
                          uint16_t fg, uint16_t bg, uint8_t scale);

#endif /* LCD_GFX_STM32_H_ */
