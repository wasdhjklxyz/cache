/*
 * Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* NOTE: This is so my stupid fuck LSP doesnt bitch about these being undefed */
#ifndef USER_LBA
#define USER_LBA 0
#endif // USER_LBA
#ifndef USER_SECTORS
#define USER_SECTORS 0
#endif // USER_SECTORS
#ifndef USER_OFFSET
#define USER_OFFSET 0
#endif // USER_OFFSET

#define COM1 0x3F8
#define ATA_IO 0x1F0
#define PDT_ADDR 0x3000
#define PTT_US 0x04
#define PDTE_USER (USER_OFFSET / 0x200000) // Each entry maps 2MB
#define USER_STACK (USER_OFFSET + 0x100000)
#define USER_CODE_SEL (0x18 | 3) // RPL=3 (FIXME: Should use gdt_sel.inc btw)
#define USER_DATA_SEL (0x20 | 3) // RPL=3 (FIXME: Should use gdt_sel.inc btw)

typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long uint64_t;

static inline void outb(uint16_t port, uint8_t val) {
  asm volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
  uint8_t ret;
  asm volatile("inb %1, %0" : "=a"(ret) : "Nd"(port));
  return ret;
}

static inline uint32_t inl(uint16_t port) {
  uint32_t ret;
  asm volatile("inl %1, %0" : "=a"(ret) : "Nd"(port));
  return ret;
}

void serial_init(void) {
  outb(COM1 + 1, 0x00); // Disable all interrupts
  outb(COM1 + 3, 0x80); // Enable DLAB (set baud rate divisor)
  outb(COM1 + 0, 0x03); // Set divisor to 3 (lo byte) 38400 baud
  outb(COM1 + 1, 0x00); //                  (hi byte)
  outb(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
  outb(COM1 + 2, 0xC7); // Enable FIFO, clear them, with 14-byte threshold
  outb(COM1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
}

void serial_putc(char c) {
  while (!(inb(COM1 + 5) & 0x20)); // Wait for transmit empty
  outb(COM1, c);
}

void serial_puts(const char *str) {
  while (*str) {
    if (*str == '\n') serial_putc('\r');
    serial_putc(*str++);
  }
}

void serial_putu32(uint32_t val) {
  int i;
  uint8_t n;
  char str[11];

  str[0] = '0';
  str[1] = 'x';
  for (i = 7; i >= 0; i--, val >>= 4) {
    n = val & 0xF;
    str[i + 2] = n < 10 ? n + '0' : n + 'A' - 10;
  }
  str[10] = '\n';

  serial_puts(str);
}

void ata_pio_read(uint32_t lba, uint8_t sectors, uint32_t *buf) {
  while (inb(ATA_IO + 7) & 0x80); // Wait for drive to be ready

  outb(ATA_IO + 2, sectors);                     // Sector count
  outb(ATA_IO + 3, (uint8_t)lba);                // LBA low
  outb(ATA_IO + 4, (uint8_t)(lba >> 8));         // LBA mid
  outb(ATA_IO + 5, (uint8_t)(lba >> 16));        // LBA high
  outb(ATA_IO + 6, 0xE0 | ((lba >> 24) & 0x0F)); // Drive/head
  outb(ATA_IO + 7, 0x20);                        // READ SECTORS command

  for (uint32_t i = 0; i < sectors; i++) {
    while (!(inb(ATA_IO + 7) & 0x80)); // Wait for drive to be ready
    for (int j = 0; j < 256; j++) {    // Read 256 words (1 sector)
      buf[i * 256 + j] = inl(ATA_IO);
    }
  }
}

void setup_user_pdte(void) {
  uint64_t *pdt = (uint64_t *)PDT_ADDR;
  pdt[PDTE_USER] |= PTT_US;
}

void enter_user_mode(void) {
  asm volatile("movq %0, %%rax\n\t"
               "movw %%ax, %%ds\n\t"
               "movw %%ax, %%es\n\t"
               "movw %%ax, %%fs\n\t"
               "movw %%ax, %%gs\n\t"
               "pushq %0\n\t"
               "pushq %1\n\t"
               "pushq $0x202\n\t"
               "pushq %2\n\t"
               "pushq %3\n\t"
               "iretq"
               :
               : "r"((uint64_t)USER_DATA_SEL), "r"((uint64_t)USER_STACK),
                 "r"((uint64_t)USER_CODE_SEL), "r"((uint64_t)USER_OFFSET)
               : "rax", "memory");
}

void kern_start(void) {
  serial_init();
  serial_puts("hello world\n");
  serial_putu32((uint32_t)USER_OFFSET);
  ata_pio_read(USER_LBA, USER_SECTORS, (uint32_t *)USER_OFFSET);
  serial_puts("user load done\n");
  setup_user_pdte();
  serial_puts("user pdte done\n");
  enter_user_mode();
  while (1) asm volatile("hlt");
}
