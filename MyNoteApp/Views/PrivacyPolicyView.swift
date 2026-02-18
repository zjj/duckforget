import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("隐私政策")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("更新日期：2026年2月18日")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("记不住鸭（以下简称“我们”）非常重视您的隐私。本隐私政策旨在说明我们如何收集、使用、存储和保护您的个人信息。")
                }
                
                Group {
                    Text("1. 信息收集")
                        .font(.headline)
                    Text("记不住鸭 是一款本地优先的笔记应用。我们不会将您的笔记内容、录音、图片等数据上传至我们的服务器。所有数据均存储在您的设备本地或您个人的 iCloud 账户中。")
                
                    Text("2. 数据使用")
                        .font(.headline)
                    Text("我们收集的任何非个人统计数据（如崩溃报告、性能数据）仅用于改进应用体验，不会用于识别个人身份。")
                
                    Text("3. 权限说明")
                        .font(.headline)
                    Text("• 麦克风：需要访问麦克风以进行语音输入和录音。\n• 语音识别：需要语音识别权限以将语音转为文字。\n• 相机：需要访问相机以拍摄照片或录像。\n• 位置信息：需要您的位置权限以在记录中插入当前位置。\n• 照片库：需要访问照片库以选择照片或视频。")
                    
                    Text("4. 第三方服务")
                        .font(.headline)
                    Text("本应用可能包含第三方SDK（如用于崩溃分析），这些服务可能会收集您的设备信息，但在未获得您授权的情况下，不会收集您的个人敏感信息。")
                    
                    Text("5. 变更通知")
                        .font(.headline)
                    Text("我们可能会不时更新本隐私政策。更新后的政策将在此页面发布。")
                    
                    Text("6. 联系我们")
                        .font(.headline)
                    Text("如果您对本隐私政策有任何疑问，请通过应用内的“关于”页面联系我们。")
                }
            }
            .padding()
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        PrivacyPolicyView()
    }
}
