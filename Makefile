SOURCES=$(shell ls src/*.nim)

synth: $(SOURCES)
	nim c -d:release -o:$@ --threads:on src/main.nim

synth-osx: $(SOURCES)
	nim c -d:osx -d:release -o:$@ --threads:on --stackTrace:off --tlsEmulation:off src/main.nim

synth-debug: $(SOURCES)
	nim c -d:debug -o:$@ --threads:on src/main.nim

run: synth
	./synth

rund: synth-debug
	./synth-debug
