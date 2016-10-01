SOURCES=$(shell ls src/*.nim)
DATE=$(shell date +%Y-%m-%d)

synth: $(SOURCES)
	nim c -d:release -o:$@ --threads:on --tlsEmulation:off src/main.nim

clang: $(SOURCES)
	nim cpp --cc:clang --verbosity:2 -d:release -o:$@ --threads:on --tlsEmulation:off src/main.nim

osx: $(SOURCES)
	nim c -d:osx -d:release -o:nimsynth.app/Contents/MacOS/nimsynth --threads:on --stackTrace:off --tlsEmulation:off src/main.nim
	rm nimsynth-${DATE}-osx.zip || true
	zip -r nimsynth-${DATE}-osx.zip nimsynth.app

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
