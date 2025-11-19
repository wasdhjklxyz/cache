;;;
;;; Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
;;;
;;; SPDX-License-Identifier: BSD-2-Clause
;;;

%include "gdt_sel.inc"

PML4T_ADDR equ 0x1000
PDPT_ADDR  equ 0x2000
PDT_ADDR   equ 0x3000

PTT_SIZE  equ 4096
PTT_ENTS  equ 512
PTTE_SIZE equ 8

PTT_P     equ 1
PTT_RW    equ 2
PTT_PS    equ (1 << 7)

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
    mov   esp, KERN_OFFSET

    mov   eax, cr4
    or    eax, 0x20 ; CR4.PAE
    mov   cr4, eax

    ;;
    ;; Clear page translation tables
    ;;
    mov   edi, PML4T_ADDR
    mov   cr3, edi
    xor   eax, eax
    mov   ecx, 0x6000 / 4 ; 24KB / 4 bytes (PML4 + PDPT + 4 PDTs)
    rep   stosd

    ;;
    ;; PML4[0] -> PDPT
    ;;
    mov   edi, PML4T_ADDR
    mov   dword [edi], PDPT_ADDR | PTT_P | PTT_RW

    ;;
    ;; PDPT[0-3] -> 4 PDTs (each covers 1GB)
    ;;
    mov   edi, PDPT_ADDR
    mov   dword [edi], PDT_ADDR | PTT_P | PTT_RW
    mov   dword [edi + 8], (PDT_ADDR + PTT_SIZE) | PTT_P | PTT_RW
    mov   dword [edi + 16], (PDT_ADDR + PTT_SIZE * 2) | PTT_P | PTT_RW
    mov   dword [edi + 24], (PDT_ADDR + PTT_SIZE * 3) | PTT_P | PTT_RW

    ;;
    ;; Fill all 4 PDTs with 2MB pages
    ;;
    mov   edi, PDT_ADDR
    xor   ebx, ebx
    or    ebx, PTT_P | PTT_RW | PTT_PS
    mov   ecx, PTT_ENTS * 4
  .loop:
    mov   [edi], ebx
    add   ebx, 0x200000 ; Next 2MB phys frame
    add   edi, 8
    loop  .loop

    mov   ecx, 0xC0000080
    rdmsr
    or    eax, 0x100 ; LME bit
    wrmsr

    mov   eax, cr0
    or    eax, 0x80000000 ; CR0.PG, CR0.PE
    mov   cr0, eax

    jmp   KERN_CODE_SEL:lmode_start

[bits 64]
lmode_start:
    mov   rsp, KERN_OFFSET ; FIXME
    call  kern_start
  .hang:
    hlt
    jmp   .hang
