import SwiftUI

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("服务协议")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("更新日期：2026年2月18日")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("欢迎使用 记不住鸭。请在使用本应用前仔细阅读以下条款。使用本应用即表示您同意遵守这些条款。")
                }
                
                Group {
                    Text("1. 许可授权")
                        .font(.headline)
                    Text("我们授予您个人的、不可转让的、非独占的许可，以便在您的设备上安装和使用 记不住鸭。")
                
                    Text("2. 用户责任")
                        .font(.headline)
                    Text("您应对使用本应用产生的所有内容负责。请勿使用本应用存储违法、侵权或令人反感的内容。由于数据主要存储在本地，请您务必自行备份重要数据。")
                
                    Text("3. 知识产权")
                        .font(.headline)
                    Text("记不住鸭 及其所有相关的知识产权（包括但不限于代码、设计、图标）均归我们所有。")
                    
                    Text("4. 免责声明")
                        .font(.headline)
                    Text("本应用按“现状”提供，不包含任何明示或暗示的保证。对于因使用本应用而导致的任何数据丢失或其它损失，我们不承担赔偿责任。")
                    
                    Text("5. 终止服务")
                        .font(.headline)
                    Text("如果您违反本协议的任何条款，我们可以随时终止您的使用许可。")
                    
                    Text("6. 法律适用")
                        .font(.headline)
                    Text("本协议受当地法律管辖。如有争议，双方应友好协商解决。")
                }
            }
            .padding()
        }
        .navigationTitle("服务协议")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        TermsOfServiceView()
    }
}
