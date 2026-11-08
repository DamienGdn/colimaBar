BINARY      = ColimaBar
APP         = ColimaBar.app
INSTALL_DIR = /Applications

.PHONY: build bundle install open test icons clean

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

test:
	swift run ColimaBarTests

# Regenerate app + menu bar icons from the SVG sources in design/.
# Requires Node.js with Playwright (npx playwright install chromium).
# Packs with Apple's iconutil when available, else scripts/pack-icns.py.
icons:
	node scripts/render-icons.mjs
	@if command -v iconutil >/dev/null 2>&1; then \
		iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns; \
	else \
		python3 scripts/pack-icns.py; \
	fi
	cp Resources/AppIcon.icns tauri/src-tauri/icons/icon.icns
	@echo "Icons updated."

clean:
	swift package clean
	rm -rf $(APP) build
