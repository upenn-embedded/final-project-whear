/* ST7735 display driver — STM32F411RE port
 *
 * Low-level interface to the TFT controller. This header exposes just
 * enough for the GFX layer (lcd_gfx.c) to talk to the hardware: init,
 * SPI byte/word send, address-window set, and the CS/DC control helpers.
 *
 * API mirrors lib/ST7735.h (AVR reference) so that lib/LCD_GFX.c-style
 * code can call it unchanged. Hardware layer drives SPI1 + three GPIOs.
 *
 *   SCK  = PA5   (SPI1_SCK,  AF5)
 *   MOSI = PA7   (SPI1_MOSI, AF5)
 *   DC   = PB6
 *   RST  = PB15
 *   CS   = PB5
 *   LITE = tied to 3V3 (no PWM)
 */

#ifndef ST7735_STM32_H_
#define ST7735_STM32_H_

#include <stdint.h>

#define LCD_WIDTH  160
#define LCD_HEIGHT 128
#define LCD_SIZE   (LCD_WIDTH * LCD_HEIGHT)

/* ST7735 command codes */
#define ST7735_NOP     0x00
#define ST7735_SWRESET 0x01
#define ST7735_RDDID   0x04
#define ST7735_RDDST   0x09
#define ST7735_SLPIN   0x10
#define ST7735_SLPOUT  0x11
#define ST7735_PTLON   0x12
#define ST7735_NORON   0x13
#define ST7735_INVOFF  0x20
#define ST7735_INVON   0x21
#define ST7735_DISPOFF 0x28
#define ST7735_DISPON  0x29
#define ST7735_CASET   0x2A
#define ST7735_RASET   0x2B
#define ST7735_RAMWR   0x2C
#define ST7735_RAMRD   0x2E
#define ST7735_PTLAR   0x30
#define ST7735_COLMOD  0x3A
#define ST7735_MADCTL  0x36
#define ST7735_FRMCTR1 0xB1
#define ST7735_FRMCTR2 0xB2
#define ST7735_FRMCTR3 0xB3
#define ST7735_INVCTR  0xB4
#define ST7735_DISSET5 0xB6
#define ST7735_PWCTR1  0xC0
#define ST7735_PWCTR2  0xC1
#define ST7735_PWCTR3  0xC2
#define ST7735_PWCTR4  0xC3
#define ST7735_PWCTR5  0xC4
#define ST7735_VMCTR1  0xC5
#define ST7735_RDID1   0xDA
#define ST7735_RDID2   0xDB
#define ST7735_RDID3   0xDC
#define ST7735_RDID4   0xDD
#define ST7735_PWCTR6  0xFC
#define ST7735_GMCTRP1 0xE0
#define ST7735_GMCTRN1 0xE1

#define MADCTL_MY  0x80
#define MADCTL_MX  0x40
#define MADCTL_MV  0x20
#define MADCTL_ML  0x10
#define MADCTL_RGB 0x00
#define MADCTL_BGR 0x08
#define MADCTL_MH  0x04

void Delay_ms(unsigned int n);
void lcd_init(void);
void sendCommands(const uint8_t *cmds, uint8_t length);
void LCD_setAddr(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1);
void SPI_ControllerTx(uint8_t data);
void SPI_ControllerTx_stream(uint8_t stream);
void SPI_ControllerTx_16bit(uint16_t data);
void SPI_ControllerTx_16bit_stream(uint16_t data);
void LCD_rotate(uint8_t r);

/* Control-line helpers exposed so GFX code can manage CS/DC during block writes */
void LCD_cs_low(void);
void LCD_cs_high(void);
void LCD_dc_cmd(void);
void LCD_dc_data(void);
void LCD_wait_idle(void); /* block until last SPI byte has finished shifting out */

#endif /* ST7735_STM32_H_ */
