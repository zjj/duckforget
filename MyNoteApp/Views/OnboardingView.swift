import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.appTheme) private var theme

    @State private var currentPage = 0

    private let pageCount = 8

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.colors.background.ignoresSafeArea()

            // Page content
            TabView(selection: $currentPage) {
                OnboardingWelcomePage().tag(0)
                OnboardingFeaturePage(
                    icon: "bolt.fill",
                    iconColor: Color.orange,
                    title: "即刻记录",
                    subtitle: "捕捉每一个灵感瞬间",
                    features: [
                        ("keyboard", "文字速记", "随手键入，自动保存，不错过任何想法"),
                        ("mic.fill", "语音输入", "说出你的想法，实时转文字"),
                        ("camera.fill", "拍照 & 扫描", "拍下文档、白板，一键识别文字"),
                        ("pencil.and.outline", "手绘涂鸦", "自由绘制草图，附加至任意记录")
                    ]
                ).tag(1)
                OnboardingDashboardPage().tag(2)
                OnboardingToolbarPage().tag(3)
                OnboardingMarkdownPage().tag(4)
                OnboardingFeaturePage(
                    icon: "tag.fill",
                    iconColor: Color.pink,
                    title: "高效整理",
                    subtitle: "标签分类，一网打尽",
                    features: [
                        ("tag.fill", "灵活标签", "自定义标签，随意分类"),
                        ("magnifyingglass", "全文搜索", "文字、录音、图片附件内容均可检索"),
                        ("calendar", "日历视图", "按日期浏览，找回过去的灵感"),
                        ("trash.slash.fill", "自动清理", "废纸篓到期自动清除，无需手动管理")
                    ]
                ).tag(5)
                OnboardingThemePage().tag(6)
                OnboardingFinishPage().tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // Bottom controls
            VStack(spacing: 16) {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(0 ..< pageCount, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? theme.colors.accent : theme.colors.border)
                            .frame(width: i == currentPage ? 20 : 8, height: 8)
                            .animation(.spring(duration: 0.3), value: currentPage)
                    }
                }

                // Buttons row
                HStack {
                    // Skip — hidden on last page
                    if currentPage < pageCount - 1 {
                        Button("跳过") {
                            currentPage = pageCount - 1
                        }
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.secondaryText)
                        .frame(width: 60, alignment: .leading)
                    } else {
                        Spacer().frame(width: 60)
                    }

                    Spacer()

                    // Next / Finish
                    Button {
                        if currentPage < pageCount - 1 {
                            withAnimation { currentPage += 1 }
                        } else {
                            appSettings.hasCompletedOnboarding = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentPage < pageCount - 1 ? "下一步" : "开始使用")
                                .fontWeight(.semibold)
                            if currentPage < pageCount - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.bold())
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .background(theme.colors.accent, in: Capsule())
                    }
                    .frame(width: 60 + 24*2 + 80, alignment: .trailing)
                }
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 48)
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
            .background(theme.colors.background)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Welcome Page

private struct OnboardingWelcomePage: View {
    @Environment(\.appTheme) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: theme.colors.shadow, radius: 16, y: 6)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.1), value: appeared)

            Spacer().frame(height: 32)

            Text("记不住鸭")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(theme.colors.primaryText)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)

            Spacer().frame(height: 12)

            Text("灵感速记，随手捕捉\n每一个珍贵的瞬间")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.colors.secondaryText)
                .lineSpacing(6)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.38), value: appeared)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .onAppear { appeared = true }
    }
}

// MARK: - Feature Page

private struct OnboardingFeaturePage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let features: [(String, String, String)]  // (symbol, title, desc)

    @Environment(\.appTheme) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Header icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.05), value: appeared)
            .padding(.bottom, 20)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(theme.colors.primaryText)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: appeared)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)

            Spacer().frame(height: 32)

            VStack(spacing: 20) {
                ForEach(Array(features.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(iconColor.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: item.0)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(iconColor)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.1)
                                .font(.headline)
                                .foregroundStyle(theme.colors.primaryText)
                            Text(item.2)
                                .font(.subheadline)
                                .foregroundStyle(theme.colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -20)
                    .animation(.easeOut(duration: 0.4).delay(0.28 + Double(idx) * 0.08), value: appeared)
                }
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

// MARK: - Dashboard Page

private struct OnboardingDashboardPage: View {
    @Environment(\.appTheme) private var theme
    @State private var appeared = false

    // Widget preview cards: (symbol, color, label)
    private let widgets: [(String, Color, String)] = [
        ("quote.bubble.fill",     Color(hex: "F5A623"), "鼓励语"),
        ("chart.bar.fill",        Color(hex: "4A90D9"), "统计"),
        ("magnifyingglass",       Color(hex: "7B68EE"), "搜索"),
        ("calendar",             Color(hex: "50C878"), "日历"),
        ("note.text.badge.plus", Color(hex: "FF6B6B"), "新建"),
        ("clock.fill",           Color(hex: "FF9F40"), "最近")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Header icon
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.indigo)
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.05), value: appeared)
            .padding(.bottom, 20)

            Text("随心定制看板")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(theme.colors.primaryText)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: appeared)

            Text("把最常用的功能放在触手可及的地方")
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)

            Spacer().frame(height: 28)

            // Mini widget grid preview
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(Array(widgets.enumerated()), id: \.offset) { idx, w in
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(w.1.opacity(0.15))
                                .frame(height: 60)
                            Image(systemName: w.0)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(w.1)
                        }
                        Text(w.2)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.65).delay(0.25 + Double(idx) * 0.06), value: appeared)
                }
            }

            Spacer().frame(height: 22)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.draw.fill")
                    .foregroundStyle(Color.indigo)
                    .font(.subheadline)
                Text("长按仪表盘任意位置即可进入编辑模式，拖拽排列、添加或删除组件。")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.65), value: appeared)

            Spacer().frame(height: 12)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .foregroundStyle(Color.indigo)
                    .font(.subheadline)
                Text("「设置 → 页面定制」 ，即可新增一个独立看板页，每页可单独配置不同组件。")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.75), value: appeared)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

// MARK: - Toolbar Page

private struct OnboardingToolbarPage: View {
    @Environment(\.appTheme) private var theme
    @State private var appeared = false

    // (symbol, accentColor, title, description)
    private let items: [(String, Color, String, String)] = [
        ("hand.point.up.left.fill",  Color(hex: "E07A20"), "大手指模式",   "放大输入工具栏按钮，方便拇指单手操作，不再误触。"),
        ("arrow.left.arrow.right",   Color(hex: "4A90D9"), "工具栏自由排序", "按个人习惯拖拽调整按钮顺序，高频功能置于最顺手的位置。"),
        ("eye.slash.fill",           Color(hex: "7B68EE"), "隐藏不用的功能", "关掉用不到的按钮，让工具栏保持简洁，减少视觉干扰。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Header icon
            ZStack {
                Circle()
                    .fill(Color(hex: "E07A20").opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color(hex: "E07A20"))
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.05), value: appeared)
            .padding(.bottom, 20)

            Text("输入工具栏，随你定制")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(theme.colors.primaryText)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: appeared)

            Text("打造最顺手的记录体验")
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)

            Spacer().frame(height: 32)

            VStack(spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(item.1.opacity(0.13))
                                .frame(width: 44, height: 44)
                            Image(systemName: item.0)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(item.1)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.2)
                                .font(.headline)
                                .foregroundStyle(theme.colors.primaryText)
                            Text(item.3)
                                .font(.subheadline)
                                .foregroundStyle(theme.colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -20)
                    .animation(.easeOut(duration: 0.4).delay(0.28 + Double(idx) * 0.1), value: appeared)
                }
            }

            Spacer().frame(height: 24)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(Color(hex: "E07A20"))
                    .font(.subheadline)
                Text("在「设置 → 工具栏」中随时调整，改动即时生效。")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.62), value: appeared)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

// MARK: - Markdown Page

private struct OnboardingMarkdownPage: View {
    @Environment(\.appTheme) private var theme
    @State private var appeared = false

    // Preview rows: (raw markdown string, rendered display)
    private let samples: [(String, String)] = [
        ("# 这是一级标题",   "大标题，醒目突出"),
        ("**加粗** / *斜体*", "强调重点内容"),
        ("`print(\"duck !\")`",         "行内代码高亮"),
        ("> 引用文字",        "摘录或备注"),
        ("- [ ] 待办事项",    "可勾选的任务清单")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Header icon
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "textformat")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.teal)
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.05), value: appeared)
            .padding(.bottom, 20)

            Text("Markdown 富文本")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(theme.colors.primaryText)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: appeared)

            Text("用简单语法，写出漂亮排版")
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)

            Spacer().frame(height: 28)

            VStack(spacing: 10) {
                ForEach(Array(samples.enumerated()), id: \.offset) { idx, s in
                    HStack(spacing: 0) {
                        // Raw syntax column
                        Text(s.0)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(theme.colors.syntaxKeyword)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.colors.syntaxCode.opacity(0.1))
                            )

                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(theme.colors.secondaryText)
                            .padding(.horizontal, 8)

                        // Description column
                        Text(s.1)
                            .font(.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -16)
                    .animation(.easeOut(duration: 0.38).delay(0.28 + Double(idx) * 0.08), value: appeared)
                }
            }

            Spacer().frame(height: 20)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye.fill")
                    .foregroundStyle(Color.teal)
                    .font(.subheadline)
                Text("点击工具栏的预览按钮，即可在编辑与渲染视图之间一键切换。")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.72), value: appeared)

            Spacer().frame(height: 12)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.teal)
                    .font(.subheadline)
                Text("不喜欢 Markdown？可在「设置 → 工具栏」中关闭该功能，恢复纯文本编辑体验。")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.82), value: appeared)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

// MARK: - Theme Page

private struct OnboardingThemePage: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.appTheme) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Header
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.05), value: appeared)
            .padding(.bottom, 20)

            Text("选一个你喜欢的主题")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(theme.colors.primaryText)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: appeared)

            Text("之后可以在设置中随时更改")
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)

            Spacer().frame(height: 32)

            VStack(spacing: 14) {
                ForEach(Array(AppTheme.allCases.enumerated()), id: \.element.id) { idx, t in
                    OnboardingThemeRow(appTheme: t, isSelected: appSettings.currentTheme == t) {
                        withAnimation(.spring(duration: 0.3)) {
                            appSettings.currentTheme = t
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.easeOut(duration: 0.4).delay(0.28 + Double(idx) * 0.07), value: appeared)
                }
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

private struct OnboardingThemeRow: View {
    let appTheme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Color swatch
                ZStack {
                    Circle()
                        .fill(appTheme.colors.accent.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: appTheme.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(appTheme.colors.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(appTheme.displayName)
                        .font(.headline)
                        .foregroundStyle(theme.colors.primaryText)
                    Text(appTheme.description)
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.border)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? theme.colors.accent : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Finish Page

private struct OnboardingFinishPage: View {
    @Environment(\.appTheme) private var theme
    @State private var appeared = false
    @State private var bouncing = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Checkmark animation
            ZStack {
                Circle()
                    .fill(theme.colors.accent.opacity(0.12))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(theme.colors.accent.opacity(0.18))
                    .frame(width: 90, height: 90)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(theme.colors.accent)
            }
            .scaleEffect(appeared ? (bouncing ? 1.06 : 1) : 0.2)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.05), value: appeared)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bouncing)

            Spacer().frame(height: 36)

            Text("一切就绪！")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(theme.colors.primaryText)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

            Spacer().frame(height: 14)

            Text("开始记录你的第一个灵感吧\n一切都会被好好保存 🐥")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.colors.secondaryText)
                .lineSpacing(6)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.easeOut(duration: 0.4).delay(0.42), value: appeared)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { bouncing = true }
        }
        .onDisappear { appeared = false; bouncing = false }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environment(AppSettings.shared)
        .environment(\.appTheme, AppSettings.shared.currentTheme)
}
