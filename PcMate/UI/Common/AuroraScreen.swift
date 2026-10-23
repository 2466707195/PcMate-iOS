import SwiftUI

/// 页面骨架：顶栏 + 滚动内容 + 底部悬浮操作条。
///
/// - `topBar`：自绘顶栏（`AppTopBar`）
/// - `content`：滚动内容
/// - `bar`：底部操作条（`GlassBar`），浮在内容之上
struct AuroraScreen<Top: View, Content: View, Bar: View>: View {

    @ViewBuilder var topBar: () -> Top
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bar: () -> Bar

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topBar()
                content()
            }
            bar()
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.bottom, 10)
        }
    }
}

/// 通用滚动内容容器：统一左右边距、卡片间距、底部留白。
struct AuroraScrollView<Content: View>: View {

    var bottomInset: CGFloat = AuroraMetrics.listBottomInset
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            // 这里**故意**不用 LazyVStack：
            // 页面里条件插入卡片（上传进度、提示条）时，Lazy 版本会整块空白，
            // 得手动滚动才重新出现。页面的子视图本来就不多，用 VStack 没有性能问题。
            VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                content()
            }
            .padding(.horizontal, AuroraMetrics.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
    }
}
