;;;
;;; Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
;;;
;;; SPDX-License-Identifier: BSD-2-Clause
;;;

%ifndef GDT_SEL_INC
%define GDT_SEL_INC

NULL_SEL       equ 0x00
KERN_CODE_SEL  equ 0x08
KERN_DATA_SEL  equ 0x10
USER_DATA_SEL  equ 0x18 | 3 ; RPL=3
USER_CODE_SEL  equ 0x20 | 3 ; RPL=3
BOOT_CODE_SEL  equ 0x28

%endif
