#include "asm.h"
#include "memlayout.h"
#include "mmu.h"

# Start the first CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

.code16                       # Assemble for 16-bit mode
.globl start
start:
  cli                         # BIOS enabled interrupts; disable.
                              # YY, From book:
                              # BIOS is a tiny operating system, but
                              # it's not running anymore and the control
                              # has been transferred to the boot loader.
                              # So we can disable interrupts. In addition,
                              # the boot loader shouldn't handle BIOS's
                              # interrupt.
                              # When xv6 is ready, we re-enable interrupt.

  # YY, From book:
  # Currently the processor is in real mode, simulating Intel 8088. 
  # In real mode, CPU sends 20-bit virtual address to memory. The extra
  # bits come from the segment selector register. The segment register
  # is usually implicitly indicated: instruction fetches use %es, data
  # read/write uses %ds, stack read/write uses %ss. 
  # x86 uses logical address, [segment:offset]. The segmentation hardware
  # translates the logical address into linear address: linearAddr = 
  # 16 * segmentRegister + offset. If paging table is enabled, linear
  # address is translated into physical address. Otherwise, the CPU
  # uses linear address as physical address.
  # The reason for the name is that linearAddr is calculated linearly.
  #             segmentation h/w              if paging used
  # logicalAddr -----------------> linearAddr -----------> physicalAddr
  #
  # As paging is not enabled by the boot loader, the CPU uses linearAddr
  # as physicalAddr at this stage. Also, an xv6 virtualAddr is the same
  # as an x86 logicalAddr. Xv6 configures the segmentation hardware to 
  # translate logicalAddr into linearAddr without change. So for boot
  # loader, virtualAddr = logicalAddr = linearAddr = physicalAddr. 

  # Zero data segment registers DS, ES, and SS.
  xorw    %ax,%ax             # Set %ax to zero
  movw    %ax,%ds             # -> Data Segment
  movw    %ax,%es             # -> Extra Segment
  movw    %ax,%ss             # -> Stack Segment

  # YY, From book:
  # A virtual [segment:offset] could yield a 21-bit physical address,
  # but Intel 8088 only addresses 20-bit memory address. So he top bit]
  # must be discarded. 
  # If the second bit of the keyboard conroller's output port is low, 
  # the 21st physical address bit is always cleared. Otherwise, the 
  # 21st bit acts normally. Xv6 would support 32-bit address, so we
  # enable the 21st bit. This's not very important.

  # Physical address line A20 is tied to zero so that the first PCs 
  # with 2 MB would run software that assumed 1 MB. Undo that.
seta20.1:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.1

  movb    $0xd1,%al               # 0xd1 -> port 0x64
  outb    %al,$0x64

seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.2

  movb    $0xdf,%al               # 0xdf -> port 0x60
  outb    %al,$0x60

  # YY, From book:
  # Real mode uses 16-bit registers. x86 provides "protected mode" to
  # enable 32-bit address. Protected mode is entered as follows:
  # 
  # 1. In protected mode, a segment register is an index into a 
  # segment descriptor table. Each entry in the table stores
  # <base physicalAddr, max virtualAddr, protection bits>. Xv6 uses
  # paging instead of segmentation. The boot loader sets up the segment
  # descriptor table gdt s.t. all segments have a base address of 0 and 
  # max virtualAddr of 4GB.
  # Instruction lgdt loads the CPU's global descripor table GDT register
  # with the value gdtdesc, pointing to the table gdt. With this setup,
  # we enable virtualAddr = physicalAddr.
  # 2. Enters protected mode by setting the CRO_PE of %cr0 to 1. This
  # doesn't immediately change how the CPU translates logical to physical
  # addresses. ljmp enables this. Now we switched form 8088 to 80386.

  # Switch from real to protected mode.  Use a bootstrap GDT that makes
  # virtual addresses map directly to physical addresses so that the
  # effective memory map doesn't change during the transition.
  # YY:
  # lgdt expects a 6-byte operand:
  # https://docs.oracle.com/cd/E19455-01/806-3773/instructionset-82/index.html
  lgdt    gdtdesc
  movl    %cr0, %eax
  orl     $CR0_PE, %eax
  movl    %eax, %cr0

//PAGEBREAK!
  # Complete the transition to 32-bit protected mode by using a long jmp
  # to reload %cs and %eip.  The segment descriptors are set up with no
  # translation, so that the mapping is still the identity mapping.

  # YY:
  # https://docs.oracle.com/cd/E19455-01/806-3773/instructionset-73/index.html
  # Meaning: Use $(SEG_KCODE<<3) as CS register and $start32 as offset.
  # 
  # For <<3, check: 
  # https://www.cs.cmu.edu/~410/doc/segments/segments.html
  # https://stackoverflow.com/a/31210001/9057530
  # When segment descriptor is used, the segment selector registers like 
  # %cs indicates the index into the descriptor table. The lowest 2 bits
  # are the priviledge level, and the 3rd-lowest bit speicifies whether
  # it refers to GDT or LDT. 
  ljmp    $(SEG_KCODE<<3), $start32

.code32  # Tell assembler to generate 32-bit code now.
start32:
  # Set up the protected-mode data segment registers
  movw    $(SEG_KDATA<<3), %ax    # Our data segment selector
  movw    %ax, %ds                # -> DS: Data Segment
  movw    %ax, %es                # -> ES: Extra Segment
  movw    %ax, %ss                # -> SS: Stack Segment
  movw    $0, %ax                 # Zero segments not ready for use
  movw    %ax, %fs                # -> FS
  movw    %ax, %gs                # -> GS

  # Set up the stack pointer and call into C.
  # YY:
  # Recall that gcc calling convention requires a stack.
  # 0xa0000 - 0x100000 is typically filled with I/O device memory regions.
  # Xv6 expects its kernel to be placed at 0x100000. The boot loader 
  # itself is at 0x7c00 through 0x7e00. Any other memory is fine. 
  # The boot loader chooses 0x7c00 ($start in this file) as the starting 
  # point of the stack and the stack grows towards 0x0000, away from 
  # the boot loader. 
  movl    $start, %esp
  call    bootmain

  # If bootmain returns (it shouldn't), trigger a Bochs
  # breakpoint if running under Bochs, then loop.
  movw    $0x8a00, %ax            # 0x8a00 -> port 0x8a00
  movw    %ax, %dx
  outw    %ax, %dx
  movw    $0x8ae0, %ax            # 0x8ae0 -> port 0x8a00
  outw    %ax, %dx
spin:
  jmp     spin

# Bootstrap GDT
.p2align 2                                # force 4 byte alignment
gdt:
  SEG_NULLASM                             # null seg
  SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)   # code seg
  SEG_ASM(STA_W, 0x0, 0xffffffff)         # data seg

gdtdesc:
  .word   (gdtdesc - gdt - 1)             # sizeof(gdt) - 1
  .long   gdt                             # address gdt

