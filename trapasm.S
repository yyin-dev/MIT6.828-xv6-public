#include "mmu.h"

  # vectors.S sends all traps here.
.globl alltraps
alltraps:
  # Build trap frame.
  pushl %ds
  pushl %es
  pushl %fs
  pushl %gs
  pushal
  
  # Set segment selectors:
  # (1) The processor sets %cs and %ss 
  # (2) alltraps sets up data segments by setting %ds and %es.
  movw $(SEG_KDATA<<3), %ax
  movw %ax, %ds
  movw %ax, %es

  # Call trap(tf), where tf=%esp
  pushl %esp # pointing to a 'struct trapframe`, as an arg to trap
  call trap
  addl $4, %esp # Pop the argument

  # Return falls through to trapret...
.globl trapret
trapret:
  popal
  popl %gs
  popl %fs
  popl %es
  popl %ds
  addl $0x8, %esp  # trapno and errcode
  iret # Pops %cs, $eip, %flags, %esp, %ss from stack
