#
# Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
#
# SPDX-License-Identifier: BSD-2-Clause
#

KERN_OFFSET := 0x7E00

boot.bin: boot.asm
	nasm -f bin -DKERN_OFFSET=$(KERN_OFFSET) $< -o $@

kern_entry.o: kern_entry.asm
	nasm -f elf64 -DKERN_OFFSET=$(KERN_OFFSET) $< -o $@

kern.o: kern.c
	gcc -masm=intel -ffreestanding -nostdlib -m64 -O0 -g -c $< -o $@

kern.bin: kern_entry.o kern.o
	ld -m elf_x86_64 -Ttext $(KERN_OFFSET) --oformat binary -o $@ $^

disk.img: boot.bin kern.bin
	dd if=/dev/zero of=$@ bs=512 count=2048
	dd if=boot.bin of=$@ bs=512 count=1 conv=notrunc
	dd if=kern.bin of=$@ bs=512 count=8064 seek=1 conv=notrunc # FIXME: Magic number

qemu: disk.img
	qemu-system-x86_64 -s -S -drive file=$<,format=raw -serial stdio -m 1M -no-reboot

clean:
	rm -f samples/*.out samples/*.log *.bin *.img *.o
