/* STM32F411RE startup — vector table and reset handler
 *
 * This file is the very first code that runs when the board powers on.
 * On Cortex-M chips the CPU boots by reading two 32-bit words from the
 * start of flash: the initial stack pointer and the address of the reset
 * handler. After that the reset handler has to set up C runtime — copy
 * initialized globals from flash into RAM, zero out uninitialized
 * globals, and then jump into main(). That's what we do below. */

#include <stdint.h>

/* These symbols don't exist in any C file — the LINKER defines them for
 * us based on the sections in stm32f411re.ld. For example _estack is the
 * top-of-stack address, and _sdata / _edata are the start/end of the
 * .data section's destination in RAM. _sidata is where that initialized
 * data lives in flash (the "image" we're about to copy into RAM). */
extern uint32_t _estack;
extern uint32_t _sdata, _edata, _sidata;
extern uint32_t _sbss, _ebss;

/* Forward-declares for functions we point to from the vector table.
 * main() is in main.c; the two IRQ handlers are weak-overridden there. */
int main(void);
void SysTick_Handler(void);
void USART1_IRQHandler(void);

/* If any interrupt we haven't explicitly wired up fires, we just spin
 * here forever. In a real product you'd probably log or reset, but for
 * a student project sitting in a while(1) is the easiest way to notice
 * "oh no, something went wrong" in the debugger. */
void Default_Handler(void) {
    while (1);
}

/* The reset handler is the C-runtime bring-up code. The Cortex-M has
 * already set SP to _estack for us before calling this. */
void Reset_Handler(void) {
    /* .data section: globals that have an initial value. Their values
     * live in flash (at _sidata), but the program needs to read/write
     * them in RAM (at _sdata..._edata), so we copy word by word. */
    uint32_t *src = &_sidata;
    uint32_t *dst = &_sdata;
    while (dst < &_edata) *dst++ = *src++;

    /* .bss section: zero-initialised globals. The C spec says uninitialised
     * globals start at zero, so we walk from _sbss to _ebss and clear. */
    dst = &_sbss;
    while (dst < &_ebss) *dst++ = 0;

    /* Enable the FPU. The F411 has a single-precision FPU but it powers
     * up disabled (any float instruction would fault). Setting bits 20-23
     * of CPACR gives the CPU full access to coprocessors 10 and 11, which
     * is what Cortex-M uses for floating-point ops. */
    *((volatile uint32_t *)0xE000ED88) |= (0xF << 20);

    /* All set — jump into our real program. If main ever returns (it
     * shouldn't on an embedded target), park the CPU here. */
    main();
    while (1);
}

/* Vector table placed at start of flash by the linker script.
 * Positions 16..N are external interrupts (IRQn). We care about:
 *   IRQn 37 = USART1 → vector slot 16 + 37 = 53
 * Unspecified slots in the designated-initializer range fall to Default_Handler.
 *
 * __attribute__((section(".isr_vector"), used)) does two things:
 *   - section: put this in a special ELF section the linker script
 *     places at address 0x08000000 (the start of flash).
 *   - used: tell the compiler not to garbage-collect this array even
 *     though nothing in our C code references it directly (the CPU
 *     itself reads it at reset). */
__attribute__((section(".isr_vector"), used))
void (* const vector_table[])(void) = {
    (void (*)(void))&_estack,   /*  0 Initial stack pointer */
    Reset_Handler,              /*  1 Reset */
    Default_Handler,            /*  2 NMI */
    Default_Handler,            /*  3 HardFault */
    Default_Handler,            /*  4 MemManage */
    Default_Handler,            /*  5 BusFault */
    Default_Handler,            /*  6 UsageFault */
    0, 0, 0, 0,                 /*  7-10 Reserved */
    Default_Handler,            /* 11 SVCall */
    Default_Handler,            /* 12 DebugMonitor */
    0,                          /* 13 Reserved */
    Default_Handler,            /* 14 PendSV */
    SysTick_Handler,            /* 15 SysTick */
    /* Designated-initialiser range: fill slots 16 through 52 with the
     * default (unused) handler in one line. GCC extension, but it's way
     * tidier than typing Default_Handler 37 times. */
    [16 ... 52] = Default_Handler,
    [53] = USART1_IRQHandler,   /* 16 + IRQn 37 */
};
