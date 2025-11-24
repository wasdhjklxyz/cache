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
#define USER_DATA_SEL (0x18 | 3) // RPL=3 (FIXME: Should use gdt_sel.inc btw)
#define USER_CODE_SEL (0x20 | 3) // RPL=3 (FIXME: Should use gdt_sel.inc btw)
#define KERN_CODE_SEL 0x08

#define MSR_EFER 0xC0000080
#define MSR_STAR 0xC0000081
#define MSR_LSTAR 0xC0000082
#define MSR_SFMASK 0xC0000084
#define MSR_GS_BASE 0xC0000101
#define MSR_KERN_GS_BASE 0xC0000102
#define EFER_SCE (1 << 0)  // Syscall extensions
#define SFMASK_IF (1 << 9) // Interrupts

// #define PIC_MASTER_CMD 0x20
// #define PIC_SLAVE_CMD 0xA0
#define PIC_MASTER_DATA 0x21
#define PIC_SLAVE_DATA 0xA1

#define SEG_G 0x08
#define SEG_DB 0x04
#define SEG_L 0x02
#define SEG_P 0x80
#define SEG_DPL3 0x60
#define SEG_S 0x10
#define SEG_E 0x08
#define SEG_DC 0x04 // Data: Segment grows down, Code -> Exec <= RPL
#define SEG_RW 0x02

typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long uint64_t;

extern void syscall_entry(void);

// #PF -> 0x0E
// #GP -> 0x0D
// #NP -> 0x0B
// #SS -> 0x0C
// #TS -> 0x0A
struct idt_gate {
  uint16_t offset_1;       // offset bits 0..15
  uint16_t selector;       // a code segment selector in GDT or LDT
  uint8_t ist;             // bits 0..2 holds Interrupt Stack Table offset
  uint8_t type_attributes; // gate type, dpl, and p fields
  uint16_t offset_2;       // offset bits 16..31
  uint32_t offset_3;       // offset bits 32..63
  uint32_t zero;           // reserved
};

struct idtr {
  uint16_t limit;
  uint64_t base;
} __attribute__((packed));

struct idt_gate idt[256] = {0};

static struct {
  uint64_t user_rsp;
  uint64_t kern_rsp;
} __attribute__((aligned(16))) swapgs_data;

static uint8_t syscall_stack[0x1000] __attribute__((aligned(16))); // 4KB

/*
static struct {
  uint32_t io_map_base;
  uint32_t r5;
  uint64_t r4;
  uint64_t r3;
  uint64_t ist7;
  uint64_t ist6;
  uint64_t ist5;
  uint64_t ist4;
  uint64_t ist3;
  uint64_t ist2;
  uint64_t ist1;
  uint64_t r2;
  uint64_t r1;
  uint64_t rsp2;
  uint64_t rsp1;
  uint64_t rsp0;
  uint64_t r0;
} __attribute__((aligned(16))) tss;
*/

struct gdt_ent {
  uint16_t limit;
  uint16_t base0;
  uint8_t base1;
  uint8_t access;
  uint8_t flags_limit;
  uint8_t base2;
} __attribute__((packed));

struct gdtr {
  uint16_t limit;
  uint64_t base;
} __attribute__((packed));

static struct {
  struct gdt_ent null;
  struct gdt_ent kern_code;
  struct gdt_ent kern_data;
  struct gdt_ent user_data;
  struct gdt_ent user_code;
} __attribute__((packed, aligned(16))) gdt = {0};

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

/* FIXME: Use __rdmsr builtin? */
static inline uint64_t rdmsr(uint64_t msr) {
  uint32_t low, high;
  asm volatile("rdmsr" : "=a"(low), "=d"(high) : "c"(msr) : "memory");
  return ((uint64_t)high << 32) | low;
}

/* FIXME: Use __wrmsr builtin? */
static inline void wrmsr(uint64_t msr, uint64_t val) {
  uint32_t low = val & 0xFFFFFFFF;
  uint32_t high = val >> 32;
  asm volatile("wrmsr" : : "c"(msr), "a"(low), "d"(high) : "memory");
}

static inline void lgdt(const struct gdtr *gdtr_ptr) {
  asm volatile("lgdt %0" : : "m"(*gdtr_ptr) : "memory");
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

void serial_putu64(uint64_t val) {
  int i;
  uint8_t n;
  char str[19];

  str[0] = '0';
  str[1] = 'x';
  for (i = 15; i >= 0; i--, val >>= 4) {
    n = val & 0xF;
    str[i + 2] = n < 10 ? n + '0' : n + 'A' - 10;
  }
  str[18] = '\n';

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
    uint8_t status;
    do {
      status = inb(ATA_IO + 7);
    } while ((status & 0x80) || !(status & 0x08)); // Wait for drive to be ready
    for (int j = 0; j < 128; j++) { // Read 128 dwords (1 sector)
      buf[i * 128 + j] = inl(ATA_IO);
    }
  }
}

void setup_user_pdte(void) {
  uint64_t *pdt = (uint64_t *)PDT_ADDR;
  pdt[PDTE_USER] |= PTT_US;
}

void generic_isr(void) {
  serial_puts("ISR!!!!!!!!!!!1!\n");
  while (1) asm volatile("hlt");
}

void setup_idt(void) {
  uint64_t isr = (uint64_t)generic_isr;
  for (int i = 0; i < 256; i++) {
    idt[i].offset_1 = isr & 0xFFFF;
    idt[i].offset_2 = (isr >> 16) & 0xFFFF;
    idt[i].offset_3 = (isr >> 32);
    idt[i].selector = KERN_CODE_SEL;
    idt[i].ist = 0;                // Interrupt stack table not used
    idt[i].type_attributes = 0x8E; // P=1, DPL=0, 64-bit interrupt gate
    idt[i].zero = 0;
  }
  struct idtr idtr = {.limit = sizeof(idt) - 1, .base = (uint64_t)&idt};
  asm volatile("lidt %0" : : "m"(idtr));
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

/* When SYSCALL executes:
 *  RCX = RIP                 # Save return address
 *  R11 = RFLAGS              # Save flags
 *  RFLAGS &= ~SFMASK         # Mask flags
 *  CS.sel = STAR[47:32]      # Load kernel CS
 *  SS.sel = STAR[47:32] + 8  # Load kernel SS
 *  RIP = LSTAR               # Jump to kernel entry
 *  CPL = 0                   # Now in kernel mode
 *
 * When SYSRET executes:
 *  RIP = RCX                        # Restore user RIP
 *  RFLAGS[31:0] = R11[31:0]         # Restore flags (lower 32 bits)
 *  RFLAGS[63:32] = 0                # Clear upper bits
 *  CS.sel = (STAR[63:48] + 16) | 3  # Load user CS (0x10 + 16 = 0x20)
 *  SS.sel = (STAR[63:48] + 8) | 3   # Load user SS (0x10 + 8 = 0x18)
 *  CPL = 3                          # Now in user mode
 */
void enable_syscall_sysret(void) {
  swapgs_data.kern_rsp = (uint64_t)&syscall_stack[0x1000];
  swapgs_data.user_rsp = 0; // Will be set on syscall entry

  wrmsr(MSR_GS_BASE, (uint64_t)&swapgs_data);
  wrmsr(MSR_KERN_GS_BASE, (uint64_t)&swapgs_data);

  uint64_t efer = rdmsr(MSR_EFER);
  efer |= EFER_SCE;
  wrmsr(MSR_EFER, efer);

  uint64_t star = 0;
  star |= ((uint64_t)KERN_CODE_SEL << 32);
  star |= ((uint64_t)((USER_CODE_SEL & ~3) - 16) << 48); // ~3 to remove RPL
  wrmsr(MSR_STAR, star);

  wrmsr(MSR_LSTAR, (uint64_t)syscall_entry);

  wrmsr(MSR_SFMASK, SFMASK_IF);
}

long syscall_dispatch(long num, long arg1, long arg2, long arg3, long arg4,
                      long arg5) {
  (void)arg2;
  (void)arg3;
  (void)arg4;
  (void)arg5;
  serial_puts("syscall!!!!!");
  serial_putu64(num);
  serial_putu64(arg1);
  serial_puts("!!!!!llacsys");
  return num;
}

void disable_pic(void) {
  outb(PIC_MASTER_DATA, 0xFF);
  outb(PIC_SLAVE_DATA, 0xFF);
}

void set_gdt_ent(struct gdt_ent *ent, uint64_t base, uint32_t limit,
                 uint8_t flags, uint8_t access) {
  ent->limit = (uint16_t)limit;
  ent->base0 = (uint16_t)base;
  ent->base1 = (uint8_t)(base >> 16);
  ent->access = access;
  ent->flags_limit = ((flags & 0xF) << 4) | ((limit >> 16) & 0x00FF);
  ent->base2 = (uint8_t)(base >> 24);
}

void setup_gdt(void) {
  // TODO: bootloader already "presaved" us a spot to put the TSS in

  /*
  uint64_t base = (uint64_t)&tss;
  uint64_t limit = sizeof(tss) - 1;

  struct tss_sel {
    uint64_t reserved;
    uint64_t base1;
    uint8_t base2;
    uint8_t flags;
    uint8_t limit1;
    uint8_t access_byte;
    uint8_t base3;
    uint16_t base4;
    uint16_t limit2;
  };
  */

  set_gdt_ent(&gdt.kern_code, 0, 0x000FFFFF, SEG_G | SEG_L,
              SEG_P | SEG_S | SEG_E | SEG_RW);
  set_gdt_ent(&gdt.kern_data, 0, 0x000FFFFF, SEG_G | SEG_DB,
              SEG_P | SEG_S | SEG_RW);
  set_gdt_ent(&gdt.user_data, 0, 0x000FFFFF, SEG_G | SEG_DB,
              SEG_P | SEG_DPL3 | SEG_S | SEG_RW);
  set_gdt_ent(&gdt.user_code, 0, 0x000FFFFF, SEG_G | SEG_L,
              SEG_P | SEG_DPL3 | SEG_S | SEG_E | SEG_RW);

  struct gdtr gdtr = {.limit = sizeof(gdt) - 1, .base = (uint64_t)&gdt};
  lgdt(&gdtr);
}

void kern_start(void) {
  serial_init();
  serial_puts("hello world\n");
  setup_gdt();
  disable_pic();
  enable_syscall_sysret();
  serial_putu32((uint32_t)USER_OFFSET);
  ata_pio_read(USER_LBA, USER_SECTORS, (uint32_t *)USER_OFFSET);
  serial_puts("user load done\n");
  setup_user_pdte();
  serial_puts("user pdte done\n");
  setup_idt();
  serial_puts("IDT setup\n");
  enter_user_mode();
  while (1) asm volatile("hlt");
}
