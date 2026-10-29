CARGO ?= $(HOME)/.cargo/bin/cargo
PLUGIN_ID = billybonks.microsandbox-monitor
PLUGIN_DIR ?= $(HOME)/.config/omarchy/plugins/$(PLUGIN_ID)
QML_FILES = ui/DisclosureWidget.qml ui/SandboxDisclosure.qml ui/Service.qml

.PHONY: build test install enable check
build:
	$(CARGO) build --release --locked

test:
	$(CARGO) test --locked
	$(CARGO) fmt -- --check

check:
	omarchy plugin validate .
	@imports=$$(mktemp -d); trap 'rm -rf "$$imports"' EXIT; \
	ln -s "$${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$$imports/qs"; \
	/usr/lib/qt6/bin/qmllint -I "$$imports" $(QML_FILES)

# Only install known runtime files, not the build tree or source checkout.
install: build
	omarchy plugin validate .
	@test ! -L "$(PLUGIN_DIR)" && test ! -L "$(PLUGIN_DIR)/ui" && test ! -L "$(PLUGIN_DIR)/bin" && test ! -L "$(PLUGIN_DIR)/docs" && test ! -L "$(PLUGIN_DIR)/docs/screenshots" || { echo "Refusing to install through a symlink" >&2; exit 1; }
	install -d "$(PLUGIN_DIR)/bin" "$(PLUGIN_DIR)/ui" "$(PLUGIN_DIR)/docs/screenshots"
	install -m 644 README.md LICENSE preview.png "$(PLUGIN_DIR)/"
	install -m 644 docs/PUBLISHING.md "$(PLUGIN_DIR)/docs/"
	install -m 644 docs/screenshots/*.png "$(PLUGIN_DIR)/docs/screenshots/"
	install -m 644 $(QML_FILES) "$(PLUGIN_DIR)/ui/"
	install -m 755 target/release/microsandbox-panel "$(PLUGIN_DIR)/bin/microsandbox-panel.new"
	mv "$(PLUGIN_DIR)/bin/microsandbox-panel.new" "$(PLUGIN_DIR)/bin/microsandbox-panel"
	install -m 644 manifest.json "$(PLUGIN_DIR)/"
	omarchy plugin validate "$(PLUGIN_DIR)"
	omarchy-shell shell rescanPlugins

enable:
	omarchy plugin enable $(PLUGIN_ID) --section right
