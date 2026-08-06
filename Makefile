.PHONY: build test dmg clean

export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

build:
	./Scripts/build-app.sh

test:
	swift test

dmg:
	./Scripts/package-dmg.sh

clean:
	rm -rf .build dist
