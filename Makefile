APP        = Nexus
BUNDLE     = build/$(APP).app
IDENTITY   = Apple Development: hibarix@163.com (RWUNZF86ZA)
BUNDLE_ID  = com.hibarix.nexus

PLUGINS_DST = $(HOME)/Library/Application Support/Nexus/Plugins

.PHONY: build bundle run clean test install-plugins

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp .build/release/$(APP) $(BUNDLE)/Contents/MacOS/
	cp Support/Info.plist $(BUNDLE)/Contents/
	cp Support/AppIcon.icns $(BUNDLE)/Contents/Resources/
	cp -R Plugins $(BUNDLE)/Contents/Resources/
	codesign --force --sign "$(IDENTITY)" --identifier $(BUNDLE_ID) $(BUNDLE)

# 开发期直接把内置 demo 插件部署到用户插件目录（app 首启也会自动 seed）
install-plugins:
	mkdir -p "$(PLUGINS_DST)"
	cp -R Plugins/* "$(PLUGINS_DST)/"
	chmod +x "$(PLUGINS_DST)/hyswitch/hyswitch.sh"
	chmod +x "$(PLUGINS_DST)/random-passwd/random-passwd.py"

# TCC 权限按 app bundle 归责，必须经 LaunchServices（open）启动，
# 直接跑裸二进制会把权限记到终端进程头上
run: bundle
	@pkill -x $(APP) 2>/dev/null || true
	open $(BUNDLE)

test:
	swift test

clean:
	rm -rf .build build
