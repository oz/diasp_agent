all: clean build

build: ender
	coffee -c -o lib/ src/

ender:
	# Building ender.js bundle
	ender build qwery bonzo
	rm ender.js
	mv ender.min.js lib/

clean:
	rm -rf ender.js ender.min.js lib/*

PHONY: all
