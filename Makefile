BINARY_NAME = vision-ocr-mcp
BUILD_DIR = .build/release
INSTALL_PATH = /usr/local/bin
VERSION = 0.1.0

.PHONY: build release install uninstall clean test run package

build:
	swift build

release:
	swift build -c release

install: release
	@if [ -w "$(INSTALL_PATH)" ]; then \
		cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_PATH)/$(BINARY_NAME); \
	else \
		sudo cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_PATH)/$(BINARY_NAME); \
	fi
	@chmod +x $(INSTALL_PATH)/$(BINARY_NAME)
	@echo "Installed $(BINARY_NAME) to $(INSTALL_PATH)"

uninstall:
	@if [ -w "$(INSTALL_PATH)/$(BINARY_NAME)" ]; then \
		rm -f $(INSTALL_PATH)/$(BINARY_NAME); \
	else \
		sudo rm -f $(INSTALL_PATH)/$(BINARY_NAME); \
	fi
	@echo "Uninstalled $(BINARY_NAME)"

clean:
	swift package clean
	rm -rf .build

test:
	swift test

run:
	swift run $(BINARY_NAME) serve --transport stdio

run-http:
	swift run $(BINARY_NAME) serve --transport http --port 8765 --ui

package: release
	@ARCH=$$(uname -m); \
	if [ "$$ARCH" = "arm64" ]; then SUFFIX="macos-arm64"; \
	else SUFFIX="macos-amd64"; fi; \
	tar czf $(BINARY_NAME)-$(VERSION)-$$SUFFIX.tar.gz -C $(BUILD_DIR) $(BINARY_NAME); \
	echo "Packaged: $(BINARY_NAME)-$(VERSION)-$$SUFFIX.tar.gz"; \
	shasum -a 256 $(BINARY_NAME)-$(VERSION)-$$SUFFIX.tar.gz

format:
	swift format --in-place --recursive Sources/ Tests/

lint:
	swift format --lint --recursive Sources/ Tests/
