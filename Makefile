SOURCES=$(shell ls src/*.nim)

synth: $(SOURCES)
	nim c -d:release -o:$@ --threads:on --tlsEmulation:off src/main.nim

clang: $(SOURCES)
	nim cpp --cc:clang --passC:"-target x86_64-apple-darwin" --passL:"-target x86_64-apple-darwin" --verbosity:2 -d:release -o:$@ --threads:on --tlsEmulation:off src/main.nim

osx: $(SOURCES)
	nim c -d:osx -d:release -o:nimsynth.app/Contents/MacOS/nimsynth --threads:on --stackTrace:off --tlsEmulation:off src/main.nim

windows: $(SOURCES)
	nim c -d:windows -d:release -o:windows/nimsynth.exe --threads:on --stackTrace:off --tlsEmulation:off src/main.nim
.PHONY: windows

synth-debug: $(SOURCES)
	nim c -d:debug --lineTrace:on --stackTrace:on -x:on --debugger:native -o:$@ --tlsEmulation:off --threads:on src/main.nim

web: $(SOURCES)
	nim c -d:release -o:web/nimsynth.html --threads:on -d:emscripten src/main.nim

run: synth
	./synth

rund: synth-debug
	./synth-debug

.PHONY: web run rund osx windows
