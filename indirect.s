/* Test program to evaluate behavior of jalr for indirect threading.
	
See the comment in jonesforth.s starting after the NEXT macro on line 305.

Basic idea of the test: create an indirect threaded word manually, and use jalr
to jump into it to see what it does in the debugger.
*/

.text

_start:
    la t1, _double /* Seed t1 by pointing to fake "double" word */
    lw t0, 0(t1)   /* Read address at _double to t0; this points to _dup now */
    addi t1, t1, 4 /* Increment t1 by 4 to point to _plus */
	lw t0, 0(t0)   /* Read the codeword of _dup into t0; now _dup_body */
    jalr x0, 0(t0) /* Jump to _dup_body */

_double:
	/* .word _double_codeword - should be here, but we dont have an interpreter so skip */
    .word _dup     /* points to the codeword in _dup */

_dup:
	.word _dup_body /* indirect threading codeword: where should we go now? */
_dup_body:
    li x1, 8
