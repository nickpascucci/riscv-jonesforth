	.set VERSION,00
	
    /* 
    REGISTER MAPPING
	
    The RISC-V integer specification lays out the following registers:

    | Register | ABI Name | Description           | Saver  |
	|----------+----------+-----------------------+--------|
	| x0       | zero     | Zero constant         | -      |
	| x1       | ra       | Return address        | Caller |
	| x2       | sp       | Stack pointer         | -      |
	| x3       | gp       | Global pointer        | -      |
	| x4       | tp       | Thread pointer        | Callee |
	| x5-x7    | t0-t2    | Temporaries           | Caller |
	| x8       | s0 / fp  | Saved / frame pointer | Callee |
	| x9       | s1       | Saved register        | Callee |
	| x10-x11  | a0-a1    | Fn args/return values | Caller |
	| x12-x17  | 12-17    | Fn args               | Caller |
	| x18-x27  | s2-s11   | Saved registers       | Callee |
	| x28-x31  | t3-t6    | Temporaries           | Caller |

	Below is the mapping from the original Jonesforth registers to the RISC-V ones.

    | x86 | RISCV |
    |-----|-------|
	| eax | t0    |
    | esi | t1    |
    */

    /* NEXT macro. Already we vary from Jonesforth slightly. There is not an
	equivalent of LODSL in RISC-V's instruction set. It does provide an
	instruction, jalr, which reads from rs1 and jumps to it (with an optional
	offset), while storing the previous value of PC + 4 bytes into rd, however
	this is not quite the same behavior as we want to increment our indirect
	register.

    Instead we emulate LODSL by using another addi instruction.

    This may be optimizable in the future. */

    .macro NEXT
	lw t0, 0(t1)                /* Load the jump target into t0. */
	addi t1, 4                  /* Increment t1, emulating LODSL to point to next word */
	/* These next two words emulate the instruction jmp *(%eax) at jonesforth.s:308 */
	lw t0, 0(t0)                /* Read the codeword of next target for indirect jump */
    jalr x0, 0(t0)              /* Jump to the codeword pointed to by t0 */
    .endm
	
