| Startup code for abirun test images: call main, exit with its result
| through F$Exit, as on OS-9 (abirun emulates it; the status is the low
| 16 bits).  a6 and the stack pointer are set up by the harness, or by
| OS-9 when the test runs there as a module.

	.text
	.globl	_start
_start:
	jsr	main(%pc)
	move.l	%d0,%d1
	trap	#0
	.word	6			| F$Exit
1:	bra.s	1b

| The module header, for elf2mod and (through elf2rof) l68, which needs
| a root psect: a reentrant program module in object code, revision 1,
| edition 0 (elf2mod's default), entered at _start; with 48 KB of stack,
| as saves' bigframe has a 40 KB frame, which runs off the data area on
| OS-9 with elf2mod's default of 3 KB (a bus error).
	.globl	__os9_typelang, __os9_attrev, __os9_edition, __os9_stack
	.globl	__os9_entry
	.set	__os9_typelang, 0x0101
	.set	__os9_attrev, 0x8001
	.set	__os9_edition, 0
	.set	__os9_stack, 0xC000
	.set	__os9_entry, _start
