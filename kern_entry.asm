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
PTT_US    equ 4
PTT_PS    equ (1 << 7)

STACK_TOP equ 0x200000 ; 2MB

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
    mov   esp, STACK_TOP

    mov   eax, cr4
    or    eax, 0x20 ; CR4.PAE
    mov   cr4, eax

    ;;
    ;; Clear page translation tables
    ;;
    mov   edi, PML4T_ADDR
    mov   cr3, edi
    xor   eax, eax
    mov   ecx, 0x3000 / 4 ; 12KB (PML4 + PDPT + PDT) / 4 bytes
    rep   stosd

    ;;
    ;; PML4[0] -> PDPT
    ;;
    mov   edi, PML4T_ADDR
    mov   dword [edi], PDPT_ADDR | PTT_US | PTT_P | PTT_RW

    ;;
    ;; PDPT[0] -> PDT
    ;;
    mov   edi, PDPT_ADDR
    mov   dword [edi], PDT_ADDR | PTT_US | PTT_P | PTT_RW

    ;;
    ;; PDT with first 1GB identity mapped with 2MB pages
    ;;
    mov   edi, PDT_ADDR
    mov   ebx, PTT_P | PTT_RW | PTT_PS
    mov   ecx, PTT_ENTS ; 512 entries = 1GB
  .identity_loop:
    mov   [edi], ebx
    add   ebx, 0x200000 ; Next 2MB phys frame
    add   edi, 8
    loop  .identity_loop

    mov   ecx, 0xC0000080
    rdmsr
    or    eax, 0x100 ; LME bit
    wrmsr

    mov   eax, cr0
    or    eax, 0x80000000 ; CR0.PG
    mov   cr0, eax

    jmp   KERN_CODE_SEL:lmode_start

[bits 64]
lmode_start:
    mov   rsp, STACK_TOP
    call  kern_start
  .hang:
    hlt
    jmp   .hang

;;
;; SYSCALL entry point - called when userspace executes SYSCALL instruction.
;; Hardware state on entry:
;;  RCX = user RIP
;;  R11 = user RFLAGS
;;  RAX = syscall number
;;  RDI, RSI, RDX, R10, R8, R9 = syscall arguments
;;  RSP = user stack
;;  CS/SS = kernel selectors (from STAR MSR)
;;  CPL = 0
;;
global syscall_entry
extern syscall_dispatch
align  16
syscall_entry:
    swapgs            ; Swap to kern GS and switch to kern stack
    mov   [gs:0], rsp ; Save user RSP
    mov   rsp, [gs:8] ; Load kernel RSP

    ;; Save syscall arguments, callee-saved registers, and user context
    push  rcx ; User RIP
    push  r11 ; User RFLAGS
    push  rbx
    push  rbp
    push  r12
    push  r13
    push  r14
    push  r15
    push  rdi
    push  rsi
    push  rdx
    push  r10
    push  r8
    push  r9

    ;; Call C dispatcher - RSI, RDX, R8, R9 already correct
    mov   rdi, rax
    mov   rcx, r10
    push  rax
    call  syscall_dispatch
    add   rsp, 8 ; Pop saved RAX (we have new return value)

    ;; Restore syscall arguments, callee-saved registers, and user context
    pop   r9
    pop   r8
    pop   r10
    pop   rdx
    pop   rsi
    pop   rdi
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    pop   rbp
    pop   rbx
    pop   r11 ; User RFLAGS
    pop   rcx ; User RIP

    ;; Restore user RSP
    mov   rsp, [gs:0]
    swapgs

    ;; Return to userspace
    o64 sysret
