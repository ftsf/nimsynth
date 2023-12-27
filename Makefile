SOURCES=$(shell find src -name '*.nim')
DATE=$(shell date +%Y-%m-%d)
NIMC=nim c
OPTS=-p:src -d:nimNoLentIterators -d:audioInput

JACK=0

ifeq ($(JACK),1)
JACK_FLAGS="-d:jack"
else
JACK_FLAGS=
endif

synth: $(SOURCES)
	${NIMC} ${OPTS} -d:release -o:$@ src/main.nim

synth-debug: $(SOURCES)
	${NIMC} ${OPTS} -d:debug -o:$@ src/main.nim

run: synth
	./synth

rund: synth-debug
	./synth-debug

.PHONY: web run rund osx windows
