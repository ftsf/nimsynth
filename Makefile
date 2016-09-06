SOURCES=$(shell ls src/*.nim)

synth: $(SOURCES)
	nim c -d:release -o:synth --threads:on src/synth.nim

synth-debug: $(SOURCES)
	nim c -d:debug -o:synth --threads:on src/synth.nim

run: synth
	./synth

rund: synth-debug
	./synth-debug
