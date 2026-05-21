BINARY      = ColimaBar
APP         = ColimaBar.app
INSTALL_DIR = /Applications

.PHONY: build bundle install clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	cp .build/release/$(BINARY) $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/colimabar.png "Resources/colimabar@2x.png" Resources/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)
	@echo "Bundle: $(APP)"

install: bundle
	rm -rf $(INSTALL_DIR)/$(APP)
	cp -r $(APP) $(INSTALL_DIR)/
	@echo "Installed: $(INSTALL_DIR)/$(APP)"

open: install
	open $(INSTALL_DIR)/$(APP)

clean:
	swift package clean
	rm -rf $(APP)
