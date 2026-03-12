import SwiftUI

struct PrivacyPolicyView: View {
    @State private var privacyText: String = "加载中..."
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(privacyText)
                    .padding()
            }
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPrivacyPolicy()
        }
    }
    
    private func loadPrivacyPolicy() {
        guard let url = Bundle.main.url(forResource: "privacypolicy", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            privacyText = "无法加载隐私政策文件"
            return
        }
        privacyText = content
    }
}

#Preview {
    NavigationView {
        PrivacyPolicyView()
    }
}
