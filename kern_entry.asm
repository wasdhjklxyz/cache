%include "gdt_sel.inc"

[bits 32]
section .text
global  _start
extern  kern_start

;;
;; We jump here after entering protected mode. First, we must reload our segment
;; registers. Note that CS has already been set due to the far jump performed to
;; get here. After this, we far jump to our kernel entry point.
;;
_start:
    mov   ax, KERN_DATA_SEL
    mov   ds, ax
    mov   es, ax
    mov   fs, ax
    mov   gs, ax
    mov   ss, ax
    mov   esp, 0x2FFFF ; FIXME: Should be KERN_DATA_TOP
    call  kern_start
  .hang:
    hlt
    jmp   .hang
