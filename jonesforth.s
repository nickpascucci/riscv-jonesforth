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

    | x86 | RISCV | Purpose              |
    |-----+-------+----------------------|
    | eax | t0    |                      |
    | esi | t1    |                      |
    | ebp | fp    | Return stack pointer |
    | esp | sp    | Data stack pointer   |
    */

    /*
    NEXT macro. Already we vary from Jonesforth slightly. There is not an
	equivalent of LODSL in RISC-V's instruction set. It does provide an
	instruction, jalr, which reads from rs1 and jumps to it (with an optional
	offset), while storing the previous value of PC + 4 bytes into rd, however
	this is not quite the same behavior as we want to increment our indirect
	register.

    Instead we emulate LODSL by using another addi instruction.

    This may be optimizable in the future. */

    .macro NEXT
	lw t0, 0(t1)                /* Load the jump target into t0. */
	addi t1, t1, 4              /* Increment t1, emulating LODSL to point to next word */
	/* These next two lines emulate the instruction jmp *(%eax) at jonesforth.s:308 */
	lw t0, 0(t0)                /* Read the codeword of next target for indirect jump */
    jalr x0, 0(t0)              /* Jump to the codeword pointed to by t0 */
    .endm

    .macro PUSHRSP reg
	addi fp, fp, -4             /* Move the stack pointer up a slot */
    sw \reg, 0(fp)              /* Store the register value into the newly allocated spot */
    .endm

    .macro POPRSP reg
    lw \reg, 0(fp)              /* Load the item on the top of the stack into reg */
	addi fp, fp, 4              /* Move the stack pointer one slot down */
    .endm

    .text
    .align 4

DOCOL:                 /* Colon interpreter. See jonesforth.s:501 */
    PUSHRSP t1         /* Push addr of executing instruction onto the r stack */
    addi t0, t0, 4     /* Advance t0 to point to first instruction in word */
    lw t1, t0          /* t1's NEXT's working register; point it at that word */
    NEXT

    .text
    .global _start
_start:
	/* Memory layout:

    We have 16KiB of memory to work with. By default, Jonesforth allocates 64 KiB :)

    - Assembly builtin words are stored into the nonvolatile flash memory.
    - The "data segment" goes into RAM, starting at 0x8000_0000. We need two regions:
	- Our return stack, which grows downwards into RAM from its start address.
    - The data stack, which grows upwards into RAM starting where the return stack ends.

    We'll restrict the return and data stacks to 512 bytes each. The user
	dictionary will start after the data stack.

    TODO The E310 supports hardware memory protection. I should use that to
	implement a canary region to protect the data segment from being overwritten
	by the data stack, and vice-versa for the end of memory.
    */
	lw sp, var_S0
    lw fp, return_stack_size
	call set_up_data_segment

    lw t1, cold_start
    NEXT

cold_start:                     /* Startup: jump to QUIT */
    .int QUIT

    .set F_IMMED,0x80
    .set F_HIDDEN,0x20
    .set F_LENMASK,0x1f

    .set  name_link_base,0

	/* Define a Forth word with high-level components */
    .macro defword name, namelen, flags=0, label, prev
    .section .rodata
    .align 4
    .global name_\label
name_\label :
    .int name_\prev             /* Link to previous word */
    .byte \flags+\namelen
    .ascii "\name"
    .align 4
    .global \label
\label :
    .int DOCOL
	/* Put list of word pointers after */
    .endm

	/* Define a Forth word with assembly implementation */
	.macro defcode name, namelen, flags=0, label, prev
	.section .rodata
    .align 4
	/* .global name_\label */
name_\label :
    .int name_\prev
    .byte \flags+\namelen
    .ascii "\name"
    .align 4
    /* .global \label */
\label :
    .int code_\label
    .text
    /* .global code_\label */
code_\label :
	/* Assembly code follows; must end with NEXT */
    .endm

	/* Pop a value from the top of the stack into a register */
	.macro pop reg
	lw \reg, 0(sp)
    addi sp, sp, -4
    .endm

	/* Push a register onto the stack */
    .macro push reg
	addi sp, sp, 4
	sw \reg, 0(sp)
    .endm

	defcode "DROP",4,,DROP,link_base
	addi sp, sp, -4
    NEXT

    defcode "SWAP",4,,SWAP,DROP
	pop t0
    pop t2
    push t0
    push t2
    NEXT

	defcode "DUP",3,,DUP,SWAP
	lw t0, 0(sp)
    push t0
    NEXT

	.text
    .set RETURN_STACK_SIZE, 512
    .set DATA_STACK_SIZE, 512

set_up_data_segment:
    /* TODO Set up data stack */


	/********************/
    /** Welcome to RAM **/
    /********************/

	.bss
    /* Forth return stack */
    .align 4
return_stack:                   /* Initial top of return stack */
    .space RETURN_STACK_SIZE
data_stack_top:                 /* Also initial top of data stack. */
    /* (They grow in opposite directions.) */
    .space RETURN_STACK_SIZE
