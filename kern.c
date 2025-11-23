/*
 * Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

void kern_start(void) {
  asm volatile("movq $0xDEADBEEF12345678, %rax");
  while (1) {
  }
}
