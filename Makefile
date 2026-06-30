.PHONY: build test dmg clean

build:
	./Scripts/build-app.sh

test:
	swift test

dmg:
	./Scripts/package-dmg.sh

clean:
	rm -rf .build dist
