import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("隐私政策")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("更新日期：2026年2月27日")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("记不住鸭（以下简称“我们”）非常重视您的隐私。本隐私政策旨在说明我们如何收集、使用、存储和保护您的个人信息。")
                }
                
                Group {
                    Text("1. 信息收集")
                        .font(.headline)
                    Text("记不住鸭 是一款本地优先的笔记应用。我们不会将您的任何文档内容、录音、图片等数据上传至我们的服务器。所有数据均存储在您的设备本地。")
                
                    Text("2. 数据使用")
                        .font(.headline)
                    Text("我们不收集、不使用、也不共享您的个人信息。我们不会通过任何第三方SDK收集您的数据，也不会将您的数据用于广告投放或其他商业用途。")
                
                    Text("3. App 权限使用说明")
                        .font(.headline)
                    
                    Text("3.1 相册/照片库权限")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("我们会在您主动选择时申请访问相册权限，用于从本地设备选择图片插入到文档中。您的图片仅在本地使用，不会未经授权上传、共享或泄露。")
                    
                    Text("3.2 相机权限")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("我们会申请相机权限，用于拍摄照片并插入到文档内容中，仅在您主动使用拍照功能时调用，不会后台拍摄或收集影像数据。")
                    
                    Text("3.3 麦克风权限")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("我们会申请麦克风权限，用于语音录制、语音识别，将录音或识别的内容插入文档，仅在您主动开启录音或语音输入时使用，不会后台录音。")
                    
                    Text("3.4 语音识别权限")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("我们会使用语音识别能力，将您的语音内容转换为文字输入到文档中，语音数据仅用于实时转换，不会被存储或上传。")
                    
                    Text("3.5 位置权限（地图服务）")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("我们会在使用地图、位置标记功能时申请位置权限，用于在文档中插入展示地图信息、标记位置。您可随时在系统设置中关闭位置授权，关闭后不影响 App 其他功能使用。")
                    
                    Text("4. 第三方服务")
                        .font(.headline)
                    Text("本应用在开发过程中，仅使用苹果官方提供的iOS SDK进行开发与功能实现，未集成、未使用任何第三方SDK、第三方插件、第三方统计、第三方广告、第三方分享及其他第三方代码库。\n\n应用运行过程中，不会通过第三方SDK收集、上传、共享您的任何个人信息。")
                    
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
