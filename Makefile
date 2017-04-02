SOURCES=$(shell find src -name '*.nim')
DATE=$(shell date +%Y-%m-%d)
NIMC=nim -p=src

JACK=0

ifeq ($(JACK),1)
JACK_FLAGS="-d:jack"
else
JACK_FLAGS=""
endif

synth: $(SOURCES)
	${NIMC} c -d:release -o:$@ $(JACK_FLAGS) --threads:on --tlsEmulation:off src/main.nim

clang: $(SOURCES)
	${NIMC} cpp --cc:clang --verbosity:2 $(JACK_FLAGS) -d:release -o:$@ --threads:on --tlsEmulation:off src/main.nim

osx: $(SOURCES)
	${NIMC} c -d:osx -d:release $(JACK_FLAGS) -o:nimsynth.app/Contents/MacOS/nimsynth --threads:on --stackTrace:off --tlsEmulation:off src/main.nim
	rm nimsynth-${DATE}-osx.zip || true
	zip -r nimsynth-${DATE}-osx.zip nimsynth.app

windows: $(SOURCES)
	${NIMC} c -d:windows -d:release $(JACK_FLAGS) -o:windows/nimsynth.exe --threads:on --stackTrace:off --tlsEmulation:off src/main.nim
.PHONY: windows

synth-debug: $(SOURCES)
	${NIMC} c -d:debug $(JACK_FLAGS) --lineTrace:on --stackTrace:on -x:on --debugger:native -o:$@ --tlsEmulation:off --threads:on src/main.nim

web: $(SOURCES)
	${NIMC} c -d:release -o:web/nimsynth.html --threads:on -d:emscripten src/main.nim

run: synth
	./synth

rund: synth-debug
	./synth-debug

.PHONY: web run rund osx windows
