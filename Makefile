synth: src/synth.nim
	nim c -d:release -o:synth --threads:on src/synth.nim

synth-debug: src/synth.nim
	nim c -d:debug -o:synth --threads:on src/synth.nim

run: synth
	./synth

rund: synth-debug
	./synth-debug
