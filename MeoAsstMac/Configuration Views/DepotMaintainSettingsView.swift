//
//  DepotMaintainSettingsView.swift
//  MAA
//
//  Created by zhangweijian on 26/9/2026.
//

import SwiftUI

struct DepotMaintainSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    @Binding var config: DepotMaintainConfiguration

    var body: some View {
        Form {
            Section {
                Toggle("任务开始前更新库存数据", isOn: $config.updateDepot)

                Text("先识别一次仓库，用最新库存计算各计划的缺口，再按计划刷取材料。库存数据来自最近一次仓库识别。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(config.plans.indices, id: \.self) { index in
                    DepotMaintainPlanRow(
                        plan: $config.plans[index],
                        useMedicine: config.useMedicine,
                        useStone: config.useStone,
                        currentInventory: viewModel.currentInventory(of: config.plans[index].dropId),
                        onDelete: { config.plans.remove(at: index) })
                }
            } header: {
                Text("保持计划")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        config.plans.append(.init())
                    } label: {
                        Label("添加计划", systemImage: "plus")
                    }
                    .buttonStyle(.plain)

                    Text("每条计划把指定材料补到目标库存：关卡填 core 关卡名（如 CE-6、AP-5、PR-A-1），材料与目标库存在计划内编辑。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("启用「吃理智药」预算", isOn: $config.useMedicine)
                    .disabled(config.plans.isEmpty)
                Toggle("启用「吃源石」预算", isOn: $config.useStone)
                    .disabled(config.plans.isEmpty)
                Toggle("使用 48 小时内过期的理智药", isOn: $config.useExpiringMedicine)
                Toggle("AUTO 代理倍率", isOn: $config.useAutoSeries)
                Toggle("仅执行第一个库存不足的计划", isOn: $config.onlyFirstInsufficientPlan)
            } header: {
                Text("关卡与战斗")
            } footer: {
                Text("未勾选「AUTO 代理倍率」时按单倍代理；勾选后按当前理智可刷的最大倍率代理，单次刷取可能超过目标库存上限。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct DepotMaintainPlanRow: View {
    @Binding var plan: DepotMaintainConfiguration.Plan
    let useMedicine: Bool
    let useStone: Bool
    let currentInventory: Int?
    let onDelete: () -> Void

    @State private var dropItems: [(name: String, id: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LabeledContent("关卡") {
                    TextField("CE-6", text: $plan.stage)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            LabeledContent("材料") {
                Picker("", selection: dropId) {
                    Text("未选择").tag(String?.none)
                    ForEach(dropItems.indices, id: \.self) { index in
                        Text(dropItems[index].name).tag(String?.some(dropItems[index].id))
                    }
                }
                .labelsHidden()
            }

            LabeledContent("目标库存") {
                HStack {
                    Text(currentInventory.map { "\($0)" } ?? "--")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help("当前库存（最近一次仓库识别）")
                    TextField("", value: $plan.dropCount, format: .number)
                        .frame(width: 110)
                }
            }

            if useMedicine {
                LabeledContent("吃理智药") {
                    HStack {
                        Toggle("", isOn: $plan.useMedicine).labelsHidden()
                        TextField("", value: $plan.medicineCount, format: .number)
                            .frame(width: 70)
                    }
                }
            }

            if useStone {
                LabeledContent("吃源石") {
                    HStack {
                        Toggle("", isOn: $plan.useStone).labelsHidden()
                        TextField("", value: $plan.stoneCount, format: .number)
                            .frame(width: 70)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: loadDropItems)
    }

    private var dropId: Binding<String?> {
        Binding {
            plan.dropId.isEmpty ? nil : plan.dropId
        } set: {
            plan.dropId = $0 ?? ""
        }
    }

    private func loadDropItems() {
        do {
            try FightConfiguration.initDropItems("zh-cn")
        } catch let err {
            print(String(localized: "Read item_index.json failed: \(err.localizedDescription)"))
        }
        dropItems = FightConfiguration.dropItems.map {
            (name: $0.item.name, id: $0.id)
        }
    }
}

struct DepotMaintainSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        DepotMaintainSettingsView(config: .constant(.init()))
            .environmentObject(MAAViewModel())
    }
}
