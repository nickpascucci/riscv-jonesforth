	.set JONES_VERSION,00

	.set UART0_BASE_ADDR,0x10013000

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
    | eax | t0    | General purpose      |
    | esi | gp    | Instruction pointer  |
    | ebp | tp    | Return stack pointer |
    | esp | sp    | Data stack pointer   |
    */

    /* TODO Investigate using compressed instruction set */

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
	lw t0, 0(gp)                /* Load the jump target into t0. */
	addi gp, gp, 4              /* Increment gp, emulating LODSL to point to next word */
	/* These next two lines emulate the instruction jmp *(%eax) at jonesforth.s:308 */
	lw t0, 0(t0)                /* Read the codeword of next target for indirect jump */
    jalr x0, 0(t0)              /* Jump to the codeword pointed to by t0 */
    .endm

    .macro PUSHRSP reg
	addi tp, tp, -4             /* Move the return stack pointer up a slot */
    sw \reg, 0(tp)              /* Store the register value into the newly allocated spot */
    .endm

    .macro POPRSP reg
    lw \reg, 0(tp)              /* Load the item on the top of the stack into reg */
	addi tp, tp, 4              /* Move the return stack pointer one slot down */
    .endm

    .text
    .align 4

DOCOL:                 /* Colon interpreter. See jonesforth.s:501 */
    PUSHRSP gp         /* Push addr of executing instruction onto the r stack */
    addi t0, t0, 4     /* Advance t0 to point to first instruction in word */
    lw gp, t0          /* gp's NEXT's working register; point it at that word */
    NEXT

    .text
    .global _start
_start:
	/* We use a fixed address space, unlike Jonesforth, so we don't need to load the DSP */
    la tp, return_stack_top     /* Load return stack address into frame pointer */
	call set_up_data_segment

    lw gp, cold_start           /* Get ready... */
    NEXT                        /* Interpret! */

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

	/* TODO What should the order of operations be for push/pop? */
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
	addi sp, sp, -4             /* Just move the stack pointer back a cell */
    NEXT

    defcode "SWAP",4,,SWAP,DROP
	pop t0
    pop t1
    push t0
    push t1
    NEXT

	defcode "DUP",3,,DUP,SWAP
	lw t0, 0(sp)
    push t0
    NEXT

	defcode "OVER",4,,OVER,DUP
    lw t0, 4(sp)
    push t0
    NEXT

    /* TODO Implement remaining core words */
    defcode "EXIT",4,,EXIT,OVER /* TODO Update the previous link when new words are added */
    POPRSP gp
    NEXT

    defcode "LIT",3,,LIT,EXIT
	lw t0, 0(gp)
	addi gp, gp, 4
    push t0
    NEXT

    defcode "!",1,,STORE,LIT
	pop t1                      /* Address to store into */
    pop t0                      /* Value to store */
    sw t0, 0(t1)
    NEXT

    defcode "@",1,,FETCH,STORE
	pop t1                      /* Address to fetch */
    lw t0, 0(t1)                /* Read into t0 */
    push t0                     /* Store value onto the stack */
    NEXT

    defcode "+!",2,,ADDSTORE,FETCH
	pop t1                      /* Address to add to */
    pop t0                      /* Amount to add */
	/* RISC-V does not have an 'addl' equivalent, so we need to expand it. */
	lw t3, 0(t1)                /* Read the value */
    add t3, t0, t3              /* Do the add */
    sw t3, 0(t1)                /* Write it back */
    NEXT

	defcode "-!",2,,SUBSTORE,ADDSTORE
	pop t1                      /* Address to subtract to */
    pop t0                      /* Amount to subtract */
	lw t3, 0(t1)                /* Read the value */
    sub t3, t0, t3              /* Do the subtraction */
    sw t3, 0(t1)                /* Write it back */
    NEXT

    defcode "C!",2,,STOREBYTE,SUBSTORE
	pop t1                      /* Address to store into */
    pop t0                      /* Data to store there */
    sb t0, 0(t1)
    NEXT

    defcode "C@",2,,FETCHBYTE,STOREBYTE
	pop t1                      /* Address to store into */
    lw x0, t0                   /* Clear t0 */
	lb t0, t1                   /* Fetch the byte from memory */
    push t0                     /* Push it onto the stack */
    NEXT

	defcode "C@C!",4,,CCOPY,FETCHBYTE
	/* TODO */
    NEXT

	defcode "CMOVE",5,,CMOVE,CCOPY
	/* TODO */
    NEXT

    .macro defvar name, namelen, flags=0, label, prev, initial=0
    defcode \name, \namelen, \flags, \label
	la t0, var_\name
    push t0
    NEXT
    .data
    .align 4
var_\name:
    .int \initial
	.endm

	defvar "STATE",5,,STATE,CCOPY
    defvar "HERE",4,,HERE,STATE
    /* defvar "LATEST",6,,LATEST,  /\* NOTE: Must point to last word in builtin dict *\/ */
	defvar "S0",4,,SZ,HERE,data_stack_top
    defvar "BASE",4,,BASE,10

	/* Define a constant with an immediate value */
    .macro defconsti name, namelen, flags=0, label, prev, value
	defcode \name, \namelen, \flags, \label, \prev
	li t0, \value
	push t0
    .endm

	/* Define a constant with an address value */
    .macro defconsta name, namelen, flags=0, label, prev, value
	defcode \name, \namelen, \flags, \label, \prev
	la t0, \value
	push t0
    .endm


    defconsti "VERSION",7,,VERSION,BASE,JONES_VERSION
    defconsta "R0",2,,RZ,VERSION,return_stack_top
	defconsta "DOCOLO",5,,__DOCOL,RZ,DOCOL
	defconsti "F_IMMED",7,,__F_IMMED,__DOCOL,F_IMMED
	defconsti "F_HIDDEN",8,,__F_HIDDEN,__F_IMMED,F_HIDDEN
	defconsti "F_LENMASK",9,,__F_LENMASK,__F_HIDDEN,F_LENMASK

    /* We omit the Linux system call bits here. */

	/* TODO Implement return stack pieces */

	/*************************/
    /** Input and Output    **/
    /*************************/

	/* TODO Allow the user to read from either UART0 or UART1 */
	/* TODO Provide KEY? and EMIT? */
    defcode "KEY",3,,KEY,__F_LENMASK
	call _KEY
	push a0
	NEXT

	/* Read a byte from UART0 and return it in t0 */
_KEY:
	li t1, UART0_BASE_ADDR      /* First, load the UART0 address */
1:
	lw t3, 0x4(t1)              /* Read the rxdata register */
	/* Bit 31 indicates rx empty. If set, value is negative. */
	bltz t3, 1b                 /* If we have no data, loop until there is some. */
	andi a0, t3, 0xFF           /* Mask out just the received byte */
    ret                         /* We have valid data so return it. */

    defcode "EMIT",4,,EMIT,KEY
    li t1, UART0_BASE_ADDR      /* First, load the UART0 address */
    pop t0                      /* Get the character to write */
1:
    lw t3, 0(t1)                /* Read the txdata register. This gives 0 if we can write. */
	bnez t3, 1b                 /* If the queue is full, loop until we can send. */
    sw t0, 0(t1)                /* Write it to the serial output*/
    NEXT

	defcode "WORD",4,,WORD,EMIT
	call _WORD
    push a0                     /* Base address of buffer */
    push a1                     /* Length of word */
    NEXT

_WORD:
1:                              /* Find first non-blank char skipping comments */
    call _KEY
	li t1, '\\'                 /* Compare to comment character and skip if needed */
    beq a0, t1, 3f
	li t1, ' '                  /* Skip whitespace */
    beq a0, t1, 1b

    la s1, word_buffer          /* Load word buffer base address into s1 (preserved by _KEY) */

2:
	sb a0, 0(s1)                /* Write the byte into the buffer */
    addi s1, s1, 1              /* Bump the address by 1 byte (stosb does this automatically) */
	call _KEY
    li t1, ' '                  /* Break on whitespace */
    bne a0, t1, 2b

    la a0, word_buffer
    sub a1, s1, a0              /* Find the length of the word and return it */
	ret

3:                              /* Skip comments to end of line */
    call _KEY
    li t1, '\n'                 /* Check whether character is end of line*/
    bne a0, t1, 3b              /* If not, go again */
    beq a0, t1, 1b              /* If it is, return to reading word */

	.data                       /* Must go in RAM */
word_buffer:
    .space 32


    defcode "NUMBER",6,,NUMBER,WORD
	/* TODO Implement NUMBER */
    NEXT

    defcode "FIND",4,,FIND,NUMBER
	pop a0                      /* Length */
	pop a1                      /* Address */
    call _FIND
	push a0                     /* Address of entry */
    NEXT

_FIND:
    la t0, var_LATEST           /* Address of last word in dictionary */
1:
    beqz t0, 4f                 /* If the pointer in t0 is null, we're at dict's end */
	/* Compare length of word */
	lw t1, x0
	lb t1, 4(t0)                /* Length field and flags */
    and t1, t1, (F_HIDDEN|F_LENMASK) /* Extract just name length (and hidden bit) */
	bne a0, t1, 3f                   /* If the length doesn't match, go around again */

	/* RISC-V does not have an instruction like repe, so we'll need to write it. */
	mv t2, a0                   /* Copy the length we were given */
	mv t3, a1                   /* Copy the address of the target string */
    lw t4, 5(t0)                /* Load starting address of dictionary name */

2:                              /* String comparison loop: */
	lw t5, 0(t3)                /* What is the next character in the target? */
    lw t6, 0(t4)                /* What is the next character in the dictionary? */
    bne t5, t6, 3f              /* If they are not the same, bail. */
	addi t2, t2, -1             /* Decrement count */
    addi t3, t3, 1              /* Advance target pointer */
    addi t4, t4, 1              /* Advance dict pointer */
	bnez t2, 2b                 /* If we have characters remaining, go check them... */

    mv a0, t0                   /* ... Else return the address! All chars match. */
	ret

3:                              /* If we find a mismatch... */
    lw t0, 0(t0)                /* Follow link field to next item */
    j 1b                        /* and go check it for compatibility */

4:                              /* Item not found! */
	lw a0, x0                   /* Return 0 */


	defcode ">CFA",4,,TCFA,FIND
	pop a0                      /* Address of dictionary entry */
	call _TCFA
    push a0
    NEXT

_TCFA:
	addi a0, a0, 4              /* Skip ahead over link pointer */
	lw t0, x0                   /* Zero out temporary */
    lb t0, 0(a0)                /* Get the length and flags byte */
    addi a0, a0, 1              /* Skip over that byte */
	and t0, t0, (F_LENMASK)     /* Extract length */
    add a0, a0, t0              /* Skip over the name */
    addi a0, a0, 3              /* Add padding for alignment: codeword is 4-byte aligned */
    andi a0, a0, ~3             /* Mask out lower two bits */
	ret

    defword ">DFA",4,,TDFA,TCFA
	/* TODO Implement TDFA */
    .int EXIT

    /*****************/
    /** Compilation **/
    /*****************/

    defcode "CREATE",6,,CREATE,TDFA
	/* TODO Define CREATE */
    NEXT

    /*****************************************/
    /** Stacks and fixed memory allocations **/
    /*****************************************/

	.text
    .set RETURN_STACK_SIZE, 512
    .set DATA_STACK_SIZE, 512

set_up_data_segment:
	/* Memory layout:

    We have 16KiB of memory to work with. By default, Jonesforth allocates 64 KiB :)

    - Assembly builtin words are stored into the nonvolatile flash memory.
    - The "data segment" goes into RAM, starting at 0x8000_0000. We need two regions:
	- Our return stack, which grows downwards into RAM from its start address.
    - The data stack, which grows upwards into RAM starting where the return stack ends.

    We'll restrict the return and data stacks to 512 bytes each. The user
	dictionary will start after the data stack. Unlike the original Jonesforth,
	we are running on bare metal and can't dynamically allocate more memory if
	we run out. Also unlike the original, this Forth will not use a buffer to
	store input as we have direct access to the hardware. Instead, we will read
	from the serial input registers. See KEY, above.

    TODO The E310 supports hardware memory protection. I should use that to
	implement a canary region to protect the data segment from being overwritten
	by the data stack, and vice-versa for the end of memory.
    */

	/********************/
    /** Welcome to RAM **/
    /********************/

	.bss
    /* Forth return stack */
    .align 4
return_stack:
    .space RETURN_STACK_SIZE
return_stack_top:               /* Initial top of return stack. Grows down. */
data_stack_top:                 /* Also initial top of data stack. Grows up. */
    .space RETURN_STACK_SIZE
