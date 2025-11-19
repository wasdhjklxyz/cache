/*
 * Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

void kern_start(void) {
  asm volatile("mov eax, 0xDEADBEEF");
  while (1) {
  }
}
