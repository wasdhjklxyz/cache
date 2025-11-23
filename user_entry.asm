;;;
;;; Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
;;;
;;; SPDX-License-Identifier: BSD-2-Clause
;;;

[bits 64]
section .text
global  _start
extern  main

;;
;; Stub for our user program
;;
_start:
    xor   rdi, rdi ; argc=0
    xor   rsi, rsi ; argv=NULL
    call  main
  .hang:
    jmp   .hang
