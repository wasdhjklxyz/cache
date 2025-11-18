void kern_start(void) {
  asm volatile("mov eax, 0xDEADBEEF");
  while (1) {
  }
}
