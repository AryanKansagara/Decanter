# Works with just the Xcode Command Line Tools; full Xcode isn't needed.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := $(if $(wildcard $(CLT_DEV)/Frameworks/Testing.framework),\
	-Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib)

.PHONY: build test integration app run dmg clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) --skip IntegrationTests

# Real downloads + real Wine (~450 MB). Cached in ~/Library/Caches/decanter-integration.
integration:
	DECANTER_INTEGRATION=1 swift test $(TEST_FLAGS) --filter IntegrationTests

app:
	scripts/bundle.sh

run: app
	open build/Decanter.app

dmg: app
	scripts/dmg.sh

clean:
	rm -rf .build build
