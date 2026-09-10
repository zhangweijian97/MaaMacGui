//
//  AutoRaiseSettingsView.swift
//  MeoAsstMac
//

import SwiftUI

struct AutoRaiseSettingsView: View {
    @Environment(NewViewModel.self) private var viewModel

    @Binding var config: AutoRaiseConfiguration

    @State private var itemNames = [String: String]()
    @State private var nameTaskToken: UUID?

    private var plan: AutoRaisePlan {
        AutoRaisePlan(json: config.planJson)
    }

    private var demand: AutoRaiseDemand? {
        guard !plan.entries.isEmpty else { return nil }
        return plan.demand(in: AutoRaiseDemandTable.shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("养成计划")
                .font(.headline)

            TextEditor(text: $config.planJson)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
                }

            planValidation

            Divider()

            Text("缺口报告")
                .font(.headline)

            gapReport
        }
        .padding()
        .task(id: AutoRaiseReportKey(items: viewModel.depot?.items, plan: config.planJson)) {
            await updateItemNames()
        }
    }

    // MARK: - 计划验证

    @ViewBuilder private var planValidation: some View {
        if plan.issues.isEmpty {
            Text("\(plan.entries.count) 条合法")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(plan.issues, id: \.self) { issue in
                    Text(issue.message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - 缺口报告

    @ViewBuilder private var gapReport: some View {
        if let inventory = viewModel.depot?.items {
            if let demand {
                let gap = demand.gap(against: inventory)
                VStack(alignment: .leading, spacing: 8) {
                    Text("共 \(gap.total) 种材料 · 缺 \(gap.shortages.count) 种")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if gap.shortages.isEmpty {
                        Text("无缺口")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("材料缺口")
                            .font(.subheadline)
                        List(gap.shortages) { item in
                            materialRow(item, showsShortfall: true)
                        }
                        .frame(minHeight: 100)
                    }

                    if !gap.satisfied.isEmpty {
                        Text("已满足 \(gap.satisfied.count) 种")
                            .font(.subheadline)
                        List(gap.satisfied) { item in
                            materialRow(item, showsShortfall: false)
                        }
                        .frame(minHeight: 60)
                    }

                    ForEach(demand.unknownCharacters, id: \.self) { name in
                        Text("需求表无此干员：\(name)")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    ForEach(demand.noData, id: \.self) { note in
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } else {
            Text("先运行一次任务识别库存")
                .foregroundStyle(.secondary)
        }
    }

    private func itemName(_ itemId: String) -> String {
        if let name = itemNames[itemId], !name.isEmpty {
            return name
        }
        return itemId
    }

    /// 缺口行与已满足行同构：名称 + 需/有，缺口行额外显示缺口量。
    @ViewBuilder private func materialRow(_ item: AutoRaiseGap.Item, showsShortfall: Bool) -> some View {
        HStack {
            Text(itemName(item.itemId))
            Spacer()
            Text("需 \(item.required) / 有 \(item.have)")
                .font(.callout)
                .foregroundStyle(.secondary)
            if showsShortfall {
                Text("×\(item.shortfall)")
                    .monospacedDigit()
            }
        }
    }

    // MARK: - 材料名

    private func updateItemNames() async {
        guard viewModel.depot?.items != nil else { return }
        guard let demand, !demand.items.isEmpty else { return }

        let token = UUID()
        nameTaskToken = token
        let names = await MAAProvider.shared.itemNames(for: demand.items.keys)
        guard !Task.isCancelled else {
            if nameTaskToken == token {
                nameTaskToken = nil
            }
            return
        }
        itemNames = names
        nameTaskToken = nil
    }
}

/// 缺口报告的重算触发键：库存或计划变化即刷新材料名。
private struct AutoRaiseReportKey: Equatable {
    let items: [String: Int]?
    let plan: String
}

struct AutoRaiseSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AutoRaiseSettingsView(config: .constant(.init()))
            .environment(NewViewModel(parent: MAAViewModel()))
    }
}
