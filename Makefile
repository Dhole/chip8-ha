.POSIX:
.SUFFIXES:

LIBS=-lc -lm -lSDL2

build:
	hare build $(LIBS) -o chip8-ha src

run:
	hare run $(LIBS) src -- $(ROM)

clean:
	rm -rf chip8-ha

.PHONY: clean run
