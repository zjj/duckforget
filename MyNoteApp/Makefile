APP_NAME = MyNoteApp
BUNDLE_ID = net.zhong.MyNoteApp
SDK = $(shell xcrun --sdk iphonesimulator --show-sdk-path)
# 自动检测架构 (arm64 或 x86_64)
ARCH = $(shell uname -m)
TARGET = $(ARCH)-apple-ios17.0-simulator
SRC = $(shell find . -name "*.swift")
DEVICE_NAME = "iPhone 17"

all: build run

build:
	@echo "正在编译 $(APP_NAME) [架构: $(ARCH)]..."
	@mkdir -p $(APP_NAME).app
	@sed -e 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
		 -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
		 -e 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' \
		 -e 's/$$(MARKETING_VERSION)/1.0/g' \
		 -e 's/$$(CURRENT_PROJECT_VERSION)/1/g' \
		 Info.plist > $(APP_NAME).app/Info.plist
	@swiftc -sdk $(SDK) -target $(TARGET) -emit-executable -o $(APP_NAME).app/$(APP_NAME) $(SRC)
	@codesign -s - --force $(APP_NAME).app/$(APP_NAME)
	@echo "编译成功: $(APP_NAME).app"

run:
	@echo "正在启动模拟器..."
	@# 尝试启动引导的设备，如果失败则尝试启动指定的设备
	@xcrun simctl bootstatus booted -b 2>/dev/null || xcrun simctl boot $(DEVICE_NAME) || echo "模拟器可能已运行"
	@echo "正在安装应用..."
	@xcrun simctl install booted $(APP_NAME).app
	@echo "正在启动引用..."
	@xcrun simctl launch booted $(BUNDLE_ID)

clean:
	@rm -rf $(APP_NAME).app
	@echo "清理完成"
