;;;
;;; Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
;;;
;;; SPDX-License-Identifier: BSD-2-Clause
;;;

%include "config.inc"

;;
;; GDT selectors
;;
NULL_SEL       equ 0x00
KERN_CODE_SEL  equ 0x08
KERN_DATA_SEL  equ 0x10
USER_CODE_SEL  equ 0x18 | 3 ; RPL=3
USER_DATA_SEL  equ 0x20 | 3 ; RPL=3

;;
;; Derived values for DAP
;;
%define TO_SEGMENT(addr) ((addr) >> 4)
%define TO_OFFSET(addr)  ((addr) & 0xF)
KERN_CODE_SEG equ TO_SEGMENT(KERN_CODE_BASE)
KERN_CODE_OFF equ TO_OFFSET(KERN_CODE_BASE)
KERN_DATA_SEG equ TO_SEGMENT(KERN_DATA_BASE)
KERN_DATA_OFF equ TO_OFFSET(KERN_DATA_BASE)
USER_CODE_SEG equ TO_SEGMENT(USER_CODE_BASE)
USER_CODE_OFF equ TO_OFFSET(USER_CODE_BASE)
USER_DATA_SEG equ TO_SEGMENT(USER_DATA_BASE)
USER_DATA_OFF equ TO_OFFSET(USER_DATA_BASE)

;;
;; Segment sizes and sector counts
;;
KERN_CODE_SIZE    equ KERN_CODE_TOP + 1
KERN_DATA_SIZE    equ KERN_DATA_TOP + 1
USER_CODE_SIZE    equ USER_CODE_TOP + 1
USER_DATA_SIZE    equ USER_DATA_TOP + 1
KERN_CODE_SECTORS equ (KERN_CODE_SIZE + 511) / 512
KERN_DATA_SECTORS equ (KERN_DATA_SIZE + 511) / 512
USER_CODE_SECTORS equ (USER_CODE_SIZE + 511) / 512
USER_DATA_SECTORS equ (USER_DATA_SIZE + 511) / 512

;;
;; Disk LBA layout
;;
KERN_CODE_LBA equ 1
KERN_DATA_LBA equ KERN_CODE_LBA + KERN_CODE_SECTORS
USER_CODE_LBA equ KERN_DATA_LBA + KERN_DATA_SECTORS
USER_DATA_LBA equ USER_CODE_LBA + USER_CODE_SECTORS
TOTAL_SECTORS equ USER_DATA_LBA + USER_DATA_SECTORS

;;
;; CPU begins execution in 16-bit real mode with the BIOS loading us at 0x7C00.
;;
[bits 16]
[org  0x7C00]

;;
;; We do not know if the BIOS loaded us to 7C00:0000 or 0000:7C00. To
;; address this, we reload CS to 0x0000 by performing a far jump.
;;
;; After this we, zero out our GPRs and set our stack to start at 0x7C00.
;;
start:
    cli
    jmp   0x0000:.flush_cs
  .flush_cs:
    xor   ax, ax
    mov   ds, ax
    mov   es, ax
    mov   fs, ax
    mov   gs, ax
    mov   ss, ax
    mov   sp, 0x7C00
    sti

;;
;; Here we use BIOS INT 13h AH=41h to check if disk read extensions are present.
;;
check_disk_read_exts:
    mov   ah, 0x41
    mov   bx, 0x55AA ; Magic
    int   0x13
    jnc   load_segments
    mov   si, str_error_bios_isr_13_41
    jmp   error

;;
;; If extensions are installed, we can use BIOS interrupt call 13h AH=42h to
;; load the kernel and user (sample) segments. We do this before switching to
;; protected mode since we'll lose access to the BIOS ISRs.
;;
load_segments:
    mov   si, dap.kern_code
    call  load_segment
    mov   si, dap.kern_data
    call  load_segment
    mov   si, dap.user_code
    call  load_segment
    mov   si, dap.user_data
    call  load_segment
    jmp   enter_protected_mode

;;
;; If extensions are installed, we can use BIOS interrupt call 13h AH=42h to
;; load the kernel and user (sample) segments. We do this before switching to
;; protected mode since we'll lose access to the BIOS ISRs.
;;
;; It is assumed SI points to the DAP to load before this procedure is called.
;;
load_segment:
    mov   ah, 0x42
    int   0x13
    jnc   .done
    mov   si, str_error_bios_isr_13_42
    jmp   error
  .done:
    ret

;;
;; Now that we have taken advantage of the BIOS ISRs, we enter protected mode.
;; To do this, we disable interrupts, load GDTR & IDTR, then set CR0.PE.
;;
enter_protected_mode:
    cli
    lgdt    [gdt.ptr]
    lidt    [idt.ptr]
    mov     eax, cr0
    or      al, 1
    mov     cr0, eax
    jmp     KERN_CODE_SEL:start_protected_mode

;;
;; This procedure prints string to the screen using BIOS INT 10h AH=0Eh
;; (teletype function) then halts when finished. It is assumed that SI points to
;; a string before it is called.
;;
error:
    mov   ax, 0x0003 ; AL=3 (80x25 16 color text video mode)
    int   0x10       ; Set the video mode using BIOS INT 10h AH=00h
    cld
    mov   bx, 0x000F ; Page 0 (DH), white foreground (DL)
    mov   ah, 0x0E
  .next_char:
    lodsb            ; Load byte from SI into AL
    test  al, al
    jz    .done      ; If AL is zero, we reached end of the string
    int   0x10
    jmp   .next_char
  .done:
    hlt

;;
;; Global Descriptor Table (GDT). Note that the first entry must be null.
;;
gdt:
  .null:
    dq    0
  .kern_code:
    dw    KERN_CODE_TOP & 0xFFFF
    dw    KERN_CODE_BASE & 0xFFFF
    db    (KERN_CODE_BASE >> 16) & 0xFF
    db    0x9A ; P=1, DPL=00, S=1, Type=1010 (code r/x)
    db    0x40 | ((KERN_CODE_TOP >> 16) & 0x0F) ; G=0, D=1, L=0, AVL=0
    db    (KERN_CODE_BASE >> 24) & 0xFF
  .kern_data:
    dw    KERN_DATA_TOP & 0xFFFF
    dw    KERN_DATA_BASE & 0xFFFF
    db    (KERN_DATA_BASE >> 16) & 0xFF
    db    0x92 ; P=1, DPL=00, S=1, Type=0010 (data r/w)
    db    0x40 | ((KERN_DATA_TOP >> 16) & 0x0F) ; G=0, D=1, L=0, AVL=0
    db    (KERN_DATA_BASE >> 24) & 0xFF
  .user_code:
    dw    USER_CODE_TOP & 0xFFFF
    dw    USER_CODE_BASE & 0xFFFF
    db    (USER_CODE_BASE >> 16) & 0xFF
    db    0xFA ; P=1, DPL=11, S=1, Type=1010 (code r/x)
    db    0x40 | ((USER_CODE_TOP >> 16) & 0x0F) ; G=0, D=1, L=0, AVL=0
    db    (USER_CODE_BASE >> 24) & 0xFF
  .user_data:
    dw    USER_DATA_TOP & 0xFFFF
    dw    USER_DATA_BASE & 0xFFFF
    db    (USER_DATA_BASE >> 16) & 0xFF
    db    0xF2 ; P=1, DPL=11, S=1, Type=0010 (data r/w)
    db    0x40 | ((USER_DATA_TOP >> 16) & 0x0F) ; G=0, D=1, L=0, AVL=0
    db    (USER_DATA_BASE >> 24) & 0xFF
  .ptr:
    dw    $ - gdt - 1 ; Limit
    dd    gdt         ; Base

;;
;; Interrupt Descriptor Table (IDT). WARNING - an empty IDT will cause all
;; NMIs to triple fault!
;;
idt:
  .ptr:
    dw    $ - gdt - 1 ; Limit
    dd    gdt         ; Base

;;
;; Disk Address Packets (DAP) - must be aligned on 4 byte boundary.
;;
dap:
    align 4
  .kern_code:
    db    0x10, 0x00
    dw    KERN_CODE_SECTORS
    dw    KERN_CODE_OFF
    dw    KERN_CODE_SEG
    dq    KERN_CODE_LBA
    align 4
  .kern_data:
    db    0x10, 0x00
    dw    KERN_DATA_SECTORS
    dw    KERN_DATA_OFF
    dw    KERN_DATA_SEG
    dq    KERN_DATA_LBA
  .user_code:
    db    0x10, 0x00
    dw    USER_CODE_SECTORS
    dw    USER_CODE_OFF
    dw    USER_CODE_SEG
    dq    USER_CODE_LBA
    align 4
  .user_data:
    db    0x10, 0x00
    dw    USER_DATA_SECTORS
    dw    USER_DATA_OFF
    dw    USER_DATA_SEG
    dq    USER_DATA_LBA

str_error_bios_isr_13_41:
    db    0x0D, 0x0A, "Error: BIOS INT 13h AH=41h: Extensions not supported", 0
str_error_bios_isr_13_42:
    db    0x0D, 0x0A, "Error: BIOS INT 13h AH=42h: Failed to read drive", 0

;;
;; We jump here after entering protected mode. First, we must reload our segment
;; registers. Note that CS has already been set due to the far jump performed to
;; get here. After this, we far jump to our kernel entry point.
;;
    [bits 32]
start_protected_mode:
    mov   ax, KERN_DATA_SEL
    mov   ds, ax
    mov   es, ax
    mov   fs, ax
    mov   gs, ax
    mov   ss, ax
    mov   esp, KERN_DATA_TOP
    jmp   KERN_CODE_SEL:KERN_CODE_BASE

;;
;; MBR magic number so BIOS marks us bootable.
;;
times 510-($-$$) db 0
dw 0xAA55
