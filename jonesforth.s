	.set JONES_VERSION,01

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
	| x12-x17  | a2-a7    | Fn args               | Caller |
	| x18-x27  | s2-s11   | Saved registers       | Callee |
	| x28-x31  | t3-t6    | Temporaries           | Caller |

	Below is the mapping from the original Jonesforth registers to the RISC-V ones.

    | x86 | RISCV   | Purpose                                |
    |-----+---------+----------------------------------------|
    | eax | various | RISCV allows more flexibility than x86 |
	|     | fp      | Current codeword pointer               |
    | esi | gp      | Next codeword pointer                  |
    | ebp | tp      | Return stack pointer                   |
    | esp | sp      | Data stack pointer                     |
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
	lw fp, 0(gp)   /* Load the jump target into fp */
	addi gp, gp, 4 /* Increment gp, emulating LODSL to point to next word */
	lw t0, 0(fp)   /* Load address pointed to by codeword */
    jr t0          /* Indirect jump to the codeword pointed to by address in fp. */
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
    .p2align 2

    .text
    .global _start
_start:
	/* We use a fixed address space, unlike Jonesforth, so we don't need to allocate memory. */
    la tp, return_stack_top     /* Load return stack address into frame pointer. */
    la sp, data_stack_top       /* Set up stack pointer. */
	/* HERE is assigned its initial value statically, at assembly time. */

    la gp, cold_start           /* Get ready... */
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
    .p2align 2
    .global name_\label
name_\label :
    .int name_\prev             /* Link to previous word */
    .byte \flags+\namelen
    .ascii "\name"
    .p2align 2
    .global \label
\label :
    .int DOCOL
	/* Put list of word pointers after */
    .endm

/*  The colon interpreter must be defined after _start for the E310 to work properly.*/
DOCOL:                 /* Colon interpreter. See jonesforth.s:501 */
    PUSHRSP gp         /* Push addr of next instr. at previous call level onto the r. stack */
    addi fp, fp, 4     /* Advance fp to point to first data word in current definition */
    mv gp, fp          /* Make the data word the "next" word to execute */
    NEXT

	/* Define a Forth word with assembly implementation */
	.macro defcode name, namelen, flags=0, label, prev
	.section .rodata
    .p2align 2
	/* .global name_\label */
name_\label :
    .int name_\prev
    .byte \flags+\namelen
    .ascii "\name"
    .p2align 2
    /* .global \label */
\label :
    .int code_\label
    .text
    /* .global code_\label */
code_\label :
	/* Assembly code follows; must end with NEXT */
    .endm

	/* 
    The return stack and data stack start at the same address. We deconflict
	their accesses without wasting space by ensuring that the return stack
	advances its pointer before pushing data and after popping, and that the
	data stack does the opposite. Thus the starting word is part of the data
	stack.
    */

    /* Pop a value from the top of the stack into a register */
	.macro pop reg
    addi sp, sp, -4
	lw \reg, 0(sp)
    .endm

	/* Push a register onto the stack */
    .macro push reg
	sw \reg, 0(sp)
	addi sp, sp, 4
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

	defcode "ROT",3,,ROT,OVER
    pop t0
    pop t1
    pop t2
    push t1
	push t0
	push t2
    NEXT

    defcode "-ROT",4,,NROT,ROT
    pop t0
    pop t1
    pop t2
	push t0
    push t2
	push t1
    NEXT

    defcode "2DROP",5,,TWODROP,NROT
    pop t0
    pop t0
    NEXT

    defcode "2DUP",4,,TWODUP,TWODROP
	lw t0, 0(sp)
    lw t1, 4(sp)
    push t1
    push t0
    NEXT

	defcode "2SWAP",5,,TWOSWAP,TWODUP
	pop t0
    pop t1
    pop t2
    pop t3
    push t1
    push t0
    push t3
    push t2
    NEXT

    defcode "?DUP",4,,QDUP,TWOSWAP
    lw t0, 0(sp)
    bnez t0, 1f
    push t0
1:  NEXT

    defcode "1+",2,,INCR,QDUP
    lw t0, 0(sp)
    addi t0, t0, 1
    sw t0, 0(sp)
    NEXT

    defcode "1-",2,,DECR,INCR
    lw t0, 0(sp)
    addi t0, t0, -1
    sw t0, 0(sp)
    NEXT

    defcode "4+",2,,INCR4,DECR
    lw t0, 0(sp)
    addi t0, t0, 4
    sw t0, 0(sp)
    NEXT

    defcode "4-",2,,DECR4,INCR4
    lw t0, 0(sp)
    addi t0, t0, -4
    sw t0, 0(sp)
    NEXT

    defcode "+",1,,ADD,DECR4
    pop t0
    lw t1, 0(sp)
    add t0, t0, t1
    sw t0, 0(sp)
    NEXT

    defcode "-",1,,SUB,ADD
    pop t0
    lw t1, 0(sp)
    sub t0, t0, t1
    sw t0, 0(sp)
    NEXT

    defcode "*",1,,MUL,SUB
    pop t0
    lw t1, 0(sp)
    mul t0, t0, t1
    sw t0, 0(sp)
    NEXT

    defcode "/MOD",4,,DIVMOD,MUL
    lw t0, 0(sp)                /* Divisor */
    lw t1, 4(sp)                /* Dividend */
    div t2, t1, t0              /* Quotient */
    rem t3, t1, t0              /* Remainder */
    sw t3, 0(sp)
    sw t2, 4(sp)
    NEXT

	/* 
    Jonesforth uses a C-style boolean. I prefer the Forth style bitmask
	approach, so here I take a different tack.

    If two bitfields are equal, then their XOR is zero. Let's check that this is
	true with a two-bit value:
	
    a/b 00 01 10 11
    00  00 01 10 11
    01  01 00 11 10
    10  10 11 00 01
    11  11 10 01 00

    Given this, we can return all ones if two values are equal by taking the
	one's complement of the XOR of the two values.
    */

    defcode "=",1,,EQU,DIVMOD
    pop t0
    lw t1, 0(sp)
    xor t0, t0, t1
    not t0, t0
	sw t0, 0(sp)
    NEXT

	/* Not-equal is the same, but we do an extra inversion to ensure we get all
	1's if the condition holds. */
    defcode "<>",2,,NEQU,EQU
    pop t0
    lw t1, 0(sp)
    xor t0, t0, t1
    not t0, t0
    not t0, t0                  /* <- Double-not */
	sw t0, 0(sp)
    NEXT

    defcode "<",1,,LT,NEQU
    /* TODO */
    NEXT

    defcode ">",1,,GT,LT
    /* TODO */
    NEXT

    defcode "<=",2,,LE,GT
    /* TODO */
    NEXT

    defcode ">=",2,,GE,LE
    /* TODO */
    NEXT

    defcode "0=",2,,ZEQU,GE
    /* TODO */
    NEXT

    defcode "0<>",3,,ZNEQU,ZEQU
    /* TODO */
    NEXT

    defcode "0<",2,,ZLT,ZNEQU
    /* TODO */
    NEXT

    defcode "0>",2,,ZGT,ZLT
    /* TODO */
    NEXT

    defcode "0<=",3,,ZLE,ZGT
    /* TODO */
    NEXT

    defcode "0>=",3,,ZGE,ZLE
    /* TODO */
    NEXT

    defcode "AND",3,,AND,ZGE
    /* TODO */
    NEXT

    defcode "OR",2,,OR,AND
    /* TODO */
    NEXT

    defcode "XOR",3,,XOR,OR
    /* TODO */
    NEXT

    defcode "INVERT",6,,INVERT,XOR
    /* TODO */
    NEXT

    /* TODO Implement remaining core words */
    defcode "EXIT",4,,EXIT,INVERT
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
    mv t0, x0                   /* Clear t0 */
	lb t0, 0(t1)                /* Fetch the byte from memory */
    push t0                     /* Push it onto the stack */
    NEXT

	defcode "C@C!",4,,CCOPY,FETCHBYTE
	/* TODO */
    NEXT

	defcode "CMOVE",5,,CMOVE,CCOPY
	/* TODO */
    NEXT

    .macro defvar name, namelen, flags=0, label, prev, initial=0
    defcode \name, \namelen, \flags, \label, \prev
	la t0, var_\name
    push t0
    NEXT
    .data
    .p2align 2
var_\name:
    .int \initial
	.endm

	defvar "STATE", 5,,STATE, CCOPY
    defvar "HERE",  4,,HERE,  STATE, data_region_start
	/* NOTE: Must point to last word in builtin dict */
    defvar "LATEST",6,,LATEST,HERE,  name_INTERPRET
	defvar "S0",    4,,SZ,    LATEST,data_stack_top
    defvar "BASE",  4,,BASE,  SZ,    10

	/* Define a constant with an immediate value */
    .macro defconsti name, namelen, flags=0, label, prev, value
	defcode \name, \namelen, \flags, \label, \prev
	li t0, \value
	push t0
	NEXT
    .endm

	/* Define a constant with an address value */
    .macro defconsta name, namelen, flags=0, label, prev, value
	defcode \name, \namelen, \flags, \label, \prev
	la t0, \value
	push t0
	NEXT
    .endm

    defconsti "VERSION",7,,VERSION,BASE,JONES_VERSION
    defconsta "R0",2,,RZ,VERSION,return_stack_top
	defconsta "DOCOLO",5,,__DOCOL,RZ,DOCOL
	defconsti "F_IMMED",7,,__F_IMMED,__DOCOL,F_IMMED
	defconsti "F_HIDDEN",8,,__F_HIDDEN,__F_IMMED,F_HIDDEN
	defconsti "F_LENMASK",9,,__F_LENMASK,__F_HIDDEN,F_LENMASK

    /* We omit the Linux system call bits here. */


	/* Push a value onto the return stack */
    defcode ">R",2,,TOR,__F_LENMASK
    pop t0
    PUSHRSP t0
    NEXT

	/* Pop a value from the return stack */
	defcode "R>",2,,FROMR,TOR
	POPRSP t0
    push t0
    NEXT

	/* Get the value of the return stack pointer */
	defcode "RSP@",4,,RSPFETCH,FROMR
	push tp
    NEXT

	/* Set the value of the return stack pointer */
	defcode "RSP!",4,,RSPSTORE,RSPFETCH
	pop tp
    NEXT

	defcode "RDROP",5,,RDROP,RSPSTORE
	addi tp, tp, 4              /* Increment return stack pointer by 1 cell */
    NEXT

	/*************************/
    /** Input and Output    **/
    /*************************/

	/* TODO Allow the user to read from either UART0 or UART1 */
	/* TODO Provide KEY? and EMIT? */
    defcode "KEY",3,,KEY,RDROP
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
	mv s2, ra
    call _KEY
	mv ra, s2
	li t1, '\\'                 /* Compare to comment character and skip if needed */
    beq a0, t1, 3f
	li t1, ' '                  /* Skip whitespace */
    ble a0, t1, 1b

    la s1, word_buffer          /* Load word buffer base address into s1 (preserved by _KEY) */

2:
	sb a0, 0(s1)                /* Write the byte into the buffer */
    addi s1, s1, 1              /* Bump the address by 1 byte (stosb does this automatically) */
    mv s2, ra
	call _KEY
    mv ra, s2
    li t1, ' '                  /* Continue on whitespace, otherwise loop back */
    bgt a0, t1, 2b

    la a0, word_buffer
    sub a1, s1, a0              /* Find the length of the word and return it */
	ret

3:                              /* Skip comments to end of line */
    mv s2, ra
    call _KEY
	mv ra, s2
    li t1, '\n'                 /* Check whether character is a linefeed */
    beq a0, t1, 1b              /* If it is, return to reading word */
    li t1, '\r'                 /* Check whether character is a carriage return*/
    beq a0, t1, 1b              /* If it is, return to reading word */
    j 3b                        /* If neither, go again */

	.data                       /* Must go in RAM */
word_buffer:
    .space 32


    defcode "NUMBER",6,,NUMBER,WORD
	call _NUMBER
    NEXT

_NUMBER:
    /* TODO Implement _NUMBER */
    ret

    defcode "FIND",4,,FIND,NUMBER
	/* Registers must be compatible with _WORD to be used by INTERPRET */
	pop a1                      /* Length */
	pop a0                      /* Address */
    call _FIND
	push a0                     /* Address of entry */
    NEXT

	/* In: a0 = address of buffer, a1 = length of word */
_FIND:
    lw t0, var_LATEST           /* Address of last word in dictionary */
1:
    beqz t0, 4f                 /* If the pointer in t0 is null, we're at dict's end */
	/* Compare length of word */
	mv t1, x0
	lb t1, 4(t0)                /* Length field and flags */
    and t1, t1, (F_HIDDEN|F_LENMASK) /* Extract just name length (and hidden bit) */
	bne a1, t1, 3f                   /* If the length doesn't match, go around again */

	/* RISC-V does not have an instruction like repe, so we'll need to write it. */
	mv t2, a1                   /* Copy the length we were given */
	mv t3, a0                   /* Copy the address of the goal string */
    addi t4, t0, 5              /* Get starting address of dictionary name (4b addr + 1b len) */
	mv t5, x0                   /* Clear temporaries */
	mv t6, x0                   /* Clear temporaries */

2:                              /* String comparison loop: */
	lb t5, 0(t3)                /* What is the next character in the goal? */
    lb t6, 0(t4)                /* What is the next character in the dictionary? */
    bne t5, t6, 3f              /* If they are not the same, bail. */
	addi t2, t2, -1             /* Decrement count */
    addi t3, t3, 1              /* Advance goal pointer */
    addi t4, t4, 1              /* Advance dict pointer */
	bnez t2, 2b                 /* If we have characters remaining, go check them... */

    mv a0, t0                   /* ... Else return the address! All chars match. */
	ret

3:                              /* If we find a mismatch... */
    lw t0, 0(t0)                /* Follow link field to next item */
    j 1b                        /* and go check it for compatibility */

4:                              /* Item not found! */
	mv a0, x0                   /* Return 0 */


	defcode ">CFA",4,,TCFA,FIND
	pop a0                      /* Address of dictionary entry */
	call _TCFA
    push a0
    NEXT

_TCFA:
	addi a0, a0, 4              /* Skip ahead over link pointer */
	mv t0, x0                   /* Zero out temporary */
    lb t0, 0(a0)                /* Get the length and flags byte */
    addi a0, a0, 1              /* Skip over that byte */
	and t0, t0, (F_LENMASK)     /* Extract length */
    add a0, a0, t0              /* Skip over the name */
    addi a0, a0, 3              /* Add padding for alignment: codeword is 4-byte aligned */
    andi a0, a0, ~3             /* Mask out lower two bits */
	ret

    defword ">DFA",4,,TDFA,TCFA
	.int TCFA                   /* >CFA (get code field address) */
	.int INCR4                  /* 4+ (add 4 to it to get to next word) */
    .int EXIT

    /*****************/
    /** Compilation **/
    /*****************/

    defcode "CREATE",6,,CREATE,TDFA
	/* TODO Define CREATE */
    NEXT

    defcode ",",1,,COMMA,CREATE
	pop a0                      /* CFA to store */
	call _COMMA
    NEXT

_COMMA:
	lw t0, var_HERE             /* Get the address in HERE */
	sw a0, 0(t0)                /* Store value at that address */
	addi t0, t0, 4              /* Increment HERE... */
	la t1, var_HERE             /* ... and store it */
	sw t0, 0(t1)
    ret

    defcode "[",1,F_IMMED,LBRAC,COMMA
	/* TODO */
    NEXT

    defcode "]",1,,RBRAC,LBRAC
	/* TODO */
    NEXT

    defcode ":",1,,COLON,RBRAC
	/* TODO */
    NEXT

    defcode ";",1,,SEMICOLON,COLON
	/* TODO */
    NEXT

	defcode "IMMEDIATE",9,F_IMMED,IMMEDIATE,SEMICOLON
	/* TODO */
    NEXT

    defcode "HIDDEN",6,,HIDDEN,IMMEDIATE
	/* TODO */
    NEXT

    defcode "HIDE",4,,HIDE,HIDDEN
	/* TODO */
    NEXT

    defcode "'",1,,TICK,HIDE
	/* TODO */
    NEXT

	defcode "BRANCH",6,,BRANCH,TICK
	lw t0, 0(gp)                /* Fetch offset from next instruction cell */
    add gp, gp, t0              /* Add the offset to the instruction pointer */
    NEXT

	defcode "0BRANCH",7,,ZBRANCH,BRANCH
	/* TODO */
    NEXT

	defcode "LITSTRING",9,,LITSTRING,ZBRANCH
	/* TODO */
    NEXT

	defcode "TELL",4,,TELL,LITSTRING
	/* TODO */
    NEXT

	defword "QUIT",4,,QUIT,TELL
    .int RZ,RSPSTORE
    .int INTERPRET
    .int BRANCH,-8
    NEXT

    defcode "INTERPRET",9,,INTERPRET,QUIT
    call _WORD                  /* Returns a0 = pointer to word, a1 = length */

    sw x0, interpret_is_lit, t0 /* Set interpret_is_lit flag to 0 */
	call _FIND                  /* Returns a0 = address of dictionary entry or 0 */
    beqz a0, 1f                 /* If 0, no entry found */

    /* Case: Found entry in dictionary. Register a0 contains the address. */
	lb s1, 4(a0)                /* Dictionary length + flags byte */
	call _TCFA                  /* Convert dictionary entry to code field address in a0 */
	andi s1, s1, F_IMMED        /* Check if IMMED flag is set */
	bnez s1, 4f                 /* If it is, jump right to execution */
	j 2f                        /* Otherwise, go to STATE-dependent behaviors */

1:
    li t1, 1
    sw t1, interpret_is_lit, t0 /* Set the flag to 1 */
	call _NUMBER                /* Returns parsed number in a0, a1 > 0 if error */
	bnez a1, 6f
    /* TODO */

2:  /* STATE dependent behavior */
	lw t0, var_STATE            /* Are we compiling or executing? */
	beqz t0, 4f                 /* If interpreting, go to executor block */

	/* Compilation */
    call _COMMA
    lw t0, interpret_is_lit     /* Was the word a literal? */
	beqz t0, 3f                 /* If not, run the next word */
    /* TODO */

3:
    NEXT

4:  /* Execution mode; expects CFA in a0 */
    lw t0, interpret_is_lit     /* Literal? */
	bnez t0, 5f                 /* If so, handle it specially */

	lw t0, 0(a0)                /* Load the codeword */
    jr t0                       /* Jump to the codeword */

5:  /* Literals */
    push a0                     /* The value is a literal, just push it */
    NEXT

6:                              /* Error handling */
	/* TODO Print error message */
	NEXT

interpret_is_lit:
    .int 0                      /* Flag to record if reading a literal */


    /*****************************************/
    /** Stacks and fixed memory allocations **/
    /*****************************************/

	.text
    .set RETURN_STACK_SIZE, 512
    .set DATA_STACK_SIZE, 512

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
    .p2align 2
return_stack:
    .space RETURN_STACK_SIZE
return_stack_top:               /* Initial top of return stack. Grows down. */
data_stack_top:                 /* Also initial top of data stack. Grows up. */
    .space RETURN_STACK_SIZE
data_region_start:              /* Initial value of HERE */
