# duckforget.com 官方网站

记不住鸭 iOS 应用的官方静态网站。

## 文件结构

```
duckforget.com/
├── index.html          # 主页
├── privacy.html        # 隐私政策
├── terms.html          # 服务协议
├── style.css           # 共享样式
├── favicon.png         # 网站图标（待替换）
└── screenshots/        # 应用截图目录（待添加）
    ├── hero.png        # Hero 区截图（主屏）
    ├── screen1.png     # 首页看板截图
    ├── screen2.png     # 笔记编辑截图
    ├── screen3.png     # 搜索页截图
    └── screen4.png     # 标签管理截图
```

## 待替换内容

1. **App Store 链接**：搜索 `href="#"` 替换为真实 App Store URL
2. **应用截图**：将截图放入 `screenshots/` 目录，取消注释 HTML 中的 `<img>` 标签
3. **Favicon**：将 App Icon 导出为 `favicon.png`（推荐 64×64 或 128×128）
4. **Hero 截图**：`index.html` Hero 区 phone mockup 内解注释 `<img>` 行

## 本地预览

```bash
# 任意静态服务器，例如：
npx serve .
# 或
python3 -m http.server 8080
```
