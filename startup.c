/* STM32F411RE startup — vector table and reset handler */

#include <stdint.h>

extern uint32_t _estack;
extern uint32_t _sdata, _edata, _sidata;
extern uint32_t _sbss, _ebss;

int main(void);
void SysTick_Handler(void);
void USART1_IRQHandler(void);

void Default_Handler(void) {
    while (1);
}

void Reset_Handler(void) {
    /* Copy .data from flash to RAM */
    uint32_t *src = &_sidata;
    uint32_t *dst = &_sdata;
    while (dst < &_edata) *dst++ = *src++;

    /* Zero .bss */
    dst = &_sbss;
    while (dst < &_ebss) *dst++ = 0;

    /* Enable FPU (CP10 + CP11 full access) */
    *((volatile uint32_t *)0xE000ED88) |= (0xF << 20);

    main();
    while (1);
}

/* Vector table placed at start of flash by the linker script.
 * Positions 16..N are external interrupts (IRQn). We care about:
 *   IRQn 37 = USART1 → vector slot 16 + 37 = 53
 * Unspecified slots in the designated-initializer range fall to Default_Handler. */
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
    [16 ... 52] = Default_Handler,
    [53] = USART1_IRQHandler,   /* 16 + IRQn 37 */
};
