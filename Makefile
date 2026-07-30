.PHONY: build test dmg clean fetch-mpv

build:
	./Scripts/build-app.sh

test:
	swift test

fetch-mpv:
	./Scripts/fetch-mpv.sh

dmg: fetch-mpv
	./Scripts/package-dmg.sh

clean:
	rm -rf .build dist
