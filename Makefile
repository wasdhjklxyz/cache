#
# Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
#
# SPDX-License-Identifier: BSD-2-Clause
#

KERN_OFFSET := 0x7E00

boot.bin: boot.asm kern.bin
	$(eval KERN_SECTORS := $(shell echo $$(( ($$(stat -f%z kern.bin 2>/dev/null || stat -c%s kern.bin) + 511) / 512 ))))
	nasm -f bin -DKERN_OFFSET=$(KERN_OFFSET) -DKERN_SECTORS=$(KERN_SECTORS) $< -o $@

kern_entry.o: kern_entry.asm
	nasm -f elf64 $< -o $@

kern.o: kern.c
	gcc -ffreestanding -nostdlib -m64 -O0 -g -c $< -o $@

kern.elf: kern_entry.o kern.o
	ld -m elf_x86_64 -Ttext $(KERN_OFFSET) -o $@ $^

kern.bin: kern.elf
	objcopy -O binary -j .text -j .rodata -j .data $< $@

disk.img: boot.bin kern.bin
	dd if=/dev/zero of=$@ bs=512 count=2048
	dd if=boot.bin of=$@ bs=512 count=1 conv=notrunc
	dd if=kern.bin of=$@ bs=512 seek=1 conv=notrunc

qemu: disk.img
	qemu-system-x86_64 -s -S -drive file=$<,format=raw -serial stdio -m 1G -no-reboot

clean:
	rm -f samples/*.out samples/*.log *.bin *.img *.o *.elf
