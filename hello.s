.globl _start

_start:
    /* Store address of UART0 in t0 */
    li t0, 0x10013000
	
	lw t1, 0x8(t0)  /* Load current TX register */
	ori  t1, t1, 1  /* Bitmask: bit 0 = 1 */
    sw t1, 0x8(t0)  /* Enable TX in UART0 */

    andi t1, t1, 0
    addi t1, t1, 72 /* Set t1 to 72 (ASCII 'H') */
	/* TODO Does this need to be a full word store? */
    sw t1, 0(t0)    /* Write t1 to addr in t0, 0 offset */
	
	/* TODO Factor out to a loop */

    andi t1, t1, 0
    addi t1, t1, 101
    sw t1, 0(t0)

    andi t1, t1, 0
    addi t1, t1, 108
    sw t1, 0(t0)

    andi t1, t1, 0
    addi t1, t1, 108
    sw t1, 0(t0)

    andi t1, t1, 0
    addi t1, t1, 111
    sw t1, 0(t0)

    andi t1, t1, 0
    addi t1, t1, 10 /* ASCII LF, '\n' */
    sw t1, 0(t0)

finish:
    beq t1, t1, finish /* End in infinite loop */
