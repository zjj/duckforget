import SwiftUI

struct AboutView: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        List {
            // App Icon and Version
            Section {
                VStack(spacing: 20) {
                    Image("AppLogo") // 使用新增加的 Logo 图片
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                    
                    VStack(spacing: 8) {
                        Text("记不住鸭")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            }
            
            // Feature Highlights
            Section(header: Text("功能特色")) {
                FeatureRow(icon: "bolt.fill", title: "灵感速记", description: "支持文本、语音、拍照、扫描、手绘等多种记录方式，捕捉每一个灵感瞬间。")
                FeatureRow(icon: "square.grid.2x2.fill", title: "个性化看板", description: "自由定制首页组件，鼓励语、统计数据、常用功能一触即达。")
                FeatureRow(icon: "tag.fill", title: "高效管理", description: "强大的标签系统分类，让您的笔记井井有条，检索更轻松。")
                FeatureRow(icon: "lock.shield.fill", title: "隐私安全", description: "所有数据本地存储，无需联网，您完全掌控个人隐私。")
            }
            
            // Legal & Agreements
            Section(header: Text("与我联系")) {
                Link(destination: URL(string: "mailto:79492390@qq.com")!) {
                    HStack {
                        Text("联系作者")
                        Spacer()
                        Image(systemName: "envelope")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("法律与条款")) {
                NavigationLink(destination: PrivacyPolicyView()) {
                    Label("隐私政策", systemImage: "hand.raised.fill")
                }
                
                NavigationLink(destination: TermsOfServiceView()) {
                    Label("服务协议", systemImage: "doc.text.fill")
                }
            }
            
            // Copyright
            Section {
                Text("© 2026 duckforget.com. All rights reserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(theme.colors.accent)
                .frame(width: 30) // Fixed width for alignment
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView {
        AboutView()
    }
}
