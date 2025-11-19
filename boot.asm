;;;
;;; Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
;;;
;;; SPDX-License-Identifier: BSD-2-Clause
;;;

%include "gdt_sel.inc"

;;
;; CPU begins execution in 16-bit real mode with the BIOS loading us at 0x7C00.
;;
[bits 16]
[org  0x7C00]

;;
;; This macro checks if the A20 line was enabled by attempting to write to two
;; addresses that would alias if A20 is disabled.
;;
;; It works by writing 0x00 to 0x1000, writing 0xFF to what should be 0x100FF0,
;; and then checking if 0x1000 was overwritten (indicating A20 line disabled).
;;
;; OUTPUT: ZF=1 (enabled), ZF=0 (disabled)
;; NOTE: Original values at test addrs are preserved
;;
%macro M_A20_CHECK 0
    push  ds
    push  es
    xor   ax, ax
    mov   ds, ax
    mov   si, 0x1000
    not   ax
    mov   es, ax
    mov   di, 0x1000         ; ES:DI = FFFF:1000 = 0x100FF0
    mov   al, byte [ds:si]   ; Save byte DS:SI
    mov   ah, byte [es:di]   ; Save byte ES:DI
    mov   byte [ds:si], 0x00 ; Set byte 0x1000 to 0x00
    mov   byte [es:di], 0xFF ; Set byte 0x100FF0 to 0xFF
    cmp   byte [ds:si], 0    ; Check if 0x1000 was overwritten
    mov   byte [es:di], ah   ; Restore ES:DI
    mov   byte [ds:si], al   ; Restore DS:SI
    pop   es
    pop   ds
%endmacro

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
;; Here we attempt to enable A20 line by trying BIOS INT 15h or via port 0x92.
;;
enable_a20_line:
    push  si
    mov   si, str_error_a20
    M_A20_CHECK
    jz    .done
    mov   ax, 0x2401 ; BIOS INT 15h enable A20 function
    int   0x15
    M_A20_CHECK
    jz    .done
    in    al, 0x92   ; Read byte from port 0x92
    or    al, 2      ; Enable bit 2
    out   0x92, al   ; Write the byte back
    M_A20_CHECK
    jz    .done
    jmp   error
  .done:
    pop   si

;;
;; Here we use BIOS INT 13h AH=41h to check if disk read extensions are present.
;;
check_disk_read_exts:
    mov   ah, 0x41
    mov   bx, 0x55AA ; Magic
    int   0x13
    jnc   load_kernel
    mov   si, str_error_bios_isr_13_41
    jmp   error

;;
;; If extensions are installed, we can use BIOS interrupt call 13h AH=42h to
;; load the kernel. We do this before switching to protected mode since we'll
;; lose access to the BIOS ISRs.
;;
load_kernel:
    mov   si, dap.kern_code
    mov   ah, 0x42
    mov   cx, 3
  .loop:
    int   0x13
    jnc   enter_protected_mode
    loop  .loop
    mov   si, str_error_bios_isr_13_42
    jmp   error

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
    jmp     KERN_CODE_SEL:KERN_OFFSET

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
    dw    0xFFFF
    dw    0
    db    0
    db    0x9A ; P=1, DPL=00, S=1, Type=1010 (code r/x)
    db    0x4F ; G=0, D=1, L=0, AVL=0
    db    0
  .kern_data:
    dw    0xFFFF
    dw    0
    db    0
    db    0x92 ; P=1, DPL=00, S=1, Type=0010 (data r/w)
    db    0x4F ; G=0, D=1, L=0, AVL=0
    db    0
  .user_code:
    dw    0xFFFF
    dw    0
    db    0
    db    0xFA ; P=1, DPL=11, S=1, Type=1010 (code r/x)
    db    0x4F ; G=0, D=1, L=0, AVL=0
    db    0
  .user_data:
    dw    0xFFFF
    dw    0
    db    0
    db    0xF2 ; P=1, DPL=11, S=1, Type=0010 (data r/w)
    db    0x4F ; G=0, D=1, L=0, AVL=0
    db    0
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
    dw    1 ; FIXME: Temporary 1 sector load "some BIOS max is 127"
    dw    KERN_OFFSET
    dw    0
    dq    1

str_error_bios_isr_13_41:
    db    0x0D, 0x0A, "Error: BIOS INT 13h AH=41h: Extensions not supported", 0
str_error_bios_isr_13_42:
    db    0x0D, 0x0A, "Error: BIOS INT 13h AH=42h: Failed to read drive", 0
str_error_a20:
    db    0x0D, 0x0A, "Error: Failed to enable A20 line", 0

;;
;; MBR magic number so BIOS marks us bootable.
;;
times 510-($-$$) db 0
dw 0xAA55
