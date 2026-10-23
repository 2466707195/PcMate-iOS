import SwiftUI

struct HomeScreen: View {

    @EnvironmentObject private var store: ConnectionStore

    /// 右上角电脑图标点开的「我的电脑」列表。
    @State private var showComputers = false
    /// 从列表里选「打开仪表盘」时用。
    @State private var presenting: Connection?

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackdrop()

                AuroraScreen {
                    // 顶部没有任何底色：一个透明的电脑图标贴在右上角
                    TabHeaderBar { showComputers = true }
                } content: {
                    AuroraScrollView(bottomInset: 118) {
                        hero
                        ComputerPickerCard()
                        hint
                    }
                } bar: {
                    EmptyView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showComputers) {
            ComputerListSheet { connection in
                showComputers = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    presenting = connection
                }
            }
        }
        .fullScreenCover(item: $presenting) { connection in
            DashboardScreen(connection: connection, store: store)
        }
    }

    // MARK: 顶部介绍卡

    private var hero: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Aurora.brandContainer)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("远程看电脑")
                            .font(AuroraFont.headlineSmall)
                            .foregroundStyle(Aurora.ink)
                            .tracking(-0.4)
                        Text("实时状态 · 进程文件 · 局域网打印 · 外网开关")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                }

                HStack(spacing: 8) {
                    StatusPill(text: "局域网直连", color: Aurora.teal)
                    StatusPill(text: "证书固定", color: Aurora.brand)
                }

                HStack(spacing: 7) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                    Text("Agent 实时推送 · SSH 自动回退")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.inkSoft)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: 右上角提示

    private var hint: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Aurora.muted)
            Text("连接历史在右上角的电脑图标里 · 共 \(store.connections.count) 台")
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.muted)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }
}
