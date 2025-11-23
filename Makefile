#
# Copyright (c) 2025, uiop <uiop@wasdhjkl.xyz>
#
# SPDX-License-Identifier: BSD-2-Clause
#

KERN_OFFSET := 0x7E00
USER_OFFSET := 0xFE00

boot.bin: boot.asm kern.bin user.bin
	$(eval KERN_SECTORS := $(shell echo $$(( ($$(stat -f%z kern.bin 2>/dev/null || stat -c%s kern.bin) + 511) / 512 ))))
	$(eval USER_SECTORS := $(shell echo $$(( ($$(stat -f%z user.bin 2>/dev/null || stat -c%s user.bin) + 511) / 512 ))))
	nasm -f bin \
		-DKERN_OFFSET=$(KERN_OFFSET) -DKERN_SECTORS=$(KERN_SECTORS) \
		-DUSER_OFFSET=$(USER_OFFSET) -DUSER_SECTORS=$(USER_SECTORS) \
		$< -o $@

kern_entry.o: kern_entry.asm
	nasm -f elf64 $< -o $@

kern.o: kern.c
	gcc -ffreestanding -nostdlib -m64 -O0 -g -c $< -o $@

kern.elf: kern_entry.o kern.o
	ld -m elf_x86_64 -Ttext $(KERN_OFFSET) -o $@ $^

kern.bin: kern.elf
	objcopy -O binary -j .text -j .rodata -j .data $< $@

user_entry.o: user_entry.asm
	nasm -f elf64 $< -o $@

user.o: user.c
	gcc -fno-stack-protector -ffreestanding -nostdlib -m64 -O0 -g -c $< -o $@

user.elf: user_entry.o user.o
	ld -m elf_x86_64 -Ttext $(USER_OFFSET) -o $@ $^

user.bin: user.elf
	objcopy -O binary -j .text -j .rodata -j .data $< $@

disk.img: boot.bin kern.bin user.bin
	# FIXME: Dogshit why we calculating this twice??
	$(eval KERN_SECTORS := $(shell echo $$(( ($$(stat -f%z kern.bin 2>/dev/null || stat -c%s kern.bin) + 511) / 512 ))))
	dd if=/dev/zero of=$@ bs=512 count=2048
	dd if=boot.bin of=$@ bs=512 count=1 conv=notrunc
	dd if=kern.bin of=$@ bs=512 seek=1 conv=notrunc
	dd if=user.bin of=$@ bs=512 seek=$$(($(KERN_SECTORS)+1)) conv=notrunc

qemu: disk.img
	qemu-system-x86_64 -s -S -drive file=$<,format=raw -m 1G -no-reboot -nographic

clean:
	rm -f samples/*.out samples/*.log *.bin *.img *.o *.elf
