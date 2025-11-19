/*
 * Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

extern void setup_paging(void);

void kern_start(void) {
  setup_paging();
  asm volatile("mov eax, 0xDEADBEEF");
  while (1) {
  }
}
