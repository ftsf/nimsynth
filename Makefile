SOURCES=$(shell find src -name '*.nim')
DATE=$(shell date +%Y-%m-%d)
NIMC=nim -p:src

JACK=0

ifeq ($(JACK),1)
JACK_FLAGS="-d:jack"
else
JACK_FLAGS=
endif

synth: $(SOURCES)
	${NIMC} c -d:release -o:$@ src/main.nim

synth-debug: $(SOURCES)
	${NIMC} c -d:debug -o:$@ src/main.nim

run: synth
	./synth

rund: synth-debug
	./synth-debug

.PHONY: web run rund osx windows
