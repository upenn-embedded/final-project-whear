# ── STM32 Nucleo-F411RE + ESP32 Feather HUZZAH32 V2 ───────────────

# ── Tools ─────────────────────────────────────────────────────────
ARM_CC      = arm-none-eabi-gcc
ARM_OBJCOPY = arm-none-eabi-objcopy
ARM_SIZE    = arm-none-eabi-size
OPENOCD     = openocd
PIO         = ~/.platformio/penv/bin/pio

# ── STM32F411RE build flags ──────────────────────────────────────
MCPU_FLAGS  = -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard
CFLAGS      = $(MCPU_FLAGS) -Os -Wall -Wextra -std=c11 \
              -ffreestanding -fdata-sections -ffunction-sections
LDFLAGS     = $(MCPU_FLAGS) -T stm32f411re.ld -nostartfiles \
              --specs=nosys.specs -Wl,--gc-sections

# Skip lib/Reference_*/ — those are vendor reference dumps, not ours.
STM32_SRC   = main.c startup.c \
              $(filter-out lib/Reference_%/%, $(wildcard lib/*/*.c))

# ── Default: build both targets ───────────────────────────────────
all: main esp

# ── STM32 (Nucleo-F411RE) ─────────────────────────────────────────
main: main.bin

main.elf: $(STM32_SRC) stm32f411re.ld
	$(ARM_CC) $(CFLAGS) $(LDFLAGS) -o $@ $(STM32_SRC)
	$(ARM_SIZE) $@

main.bin: main.elf
	$(ARM_OBJCOPY) -O binary $< $@

flash-main: main.elf
	$(OPENOCD) -f board/st_nucleo_f4.cfg \
	           -c "program $< verify reset exit"

monitor-main:
	@echo "Opening ST-Link VCOM at 115200 (Ctrl-A, k, y to exit)"
	tio /dev/tty.usbmodem* -b 115200

# ── ESP32 (Feather HUZZAH32 V2) ───────────────────────────────────
esp:
	cd wifi && $(PIO) run

flash-esp: esp
	cd wifi && $(PIO) run --target upload

monitor-esp:
	cd wifi && $(PIO) device monitor

# ── Combined ──────────────────────────────────────────────────────
flash: flash-main flash-esp

clean:
	rm -f *.elf *.bin *.hex *.o
	cd wifi && $(PIO) run --target clean 2>/dev/null || true

.PHONY: all main esp flash flash-main flash-esp monitor-main monitor-esp clean
