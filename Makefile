.PHONY: build
build:
	./build.sh

.PHONY: build-on-arm64
build-on-arm64:
	CROSS_COMPILE_X86=1 ./build.sh
