include config.mk

samples/seq-writes.out: samples/seq-writes.c
	gcc -O0 -g -o $@ $<

samples/seq-writes.log: samples/seq-writes.out
	valgrind --tool=lackey --trace-mem=yes --log-file=$@ $<

boot.bin: boot.asm
	nasm -f bin $(NASM_DEFINES) $< -o $@

disk.img: boot.bin
	dd if=/dev/zero of=$@ bs=512 count=2048
	dd if=$< of=$@ bs=512 count=1 conv=notrunc

clean:
	rm -f samples/*.out samples/*.log *.bin *.img
