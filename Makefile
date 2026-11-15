# Works with just the Xcode Command Line Tools; full Xcode isn't needed.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := $(if $(wildcard $(CLT_DEV)/Frameworks/Testing.framework),\
	-Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib)

.PHONY: build test app run dmg clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	scripts/bundle.sh

run: app
	open build/Decanter.app

dmg: app
	scripts/dmg.sh

clean:
	rm -rf .build build
