include config.mk

boot.bin: boot.asm
	nasm -f bin $(NASM_DEFINES) $< -o $@

kern_entry.o: kern_entry.asm
	nasm -f elf64 $(NASM_DEFINES) $< -o $@

kern.o: kern.c
	gcc -masm=intel -ffreestanding -nostdlib -m64 -O0 -g -c $< -o $@

kern.bin: kern_entry.o kern.o
	ld -m elf_x86_64 -Ttext $(KERN_CODE_BASE) --oformat binary -o $@ $^

disk.img: boot.bin kern.bin
	dd if=/dev/zero of=$@ bs=512 count=2048
	dd if=boot.bin of=$@ bs=512 count=1 conv=notrunc
	dd if=kern.bin of=$@ bs=512 count=$(KERN_CODE_SECTORS) seek=$(KERN_CODE_LBA) conv=notrunc

qemu: disk.img
	qemu-system-x86_64 -s -S -drive file=$<,format=raw -serial stdio -m 1M -no-reboot

clean:
	rm -f samples/*.out samples/*.log *.bin *.img *.o
