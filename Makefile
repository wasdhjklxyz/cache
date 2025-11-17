samples/seq-writes.out: samples/seq-writes.c
	gcc -O0 -g -o $@ $<

samples/seq-writes.log: samples/seq-writes.out
	valgrind --tool=lackey --trace-mem=yes --log-file=$@ $<

clean:
	rm -f samples/*.out samples/*.log
