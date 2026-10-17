//
//  OperProgressSettingsView.swift
//  MAA
//
//  干员培养配置页：工具箱链接 + 折叠/清空/解析剪贴板 + 可搜索添加 + 计划卡片列表。
//  交互对齐 WPF `OperProgressTaskUserControl`（v6.19.0-beta.1）。
//

import AppKit
import SwiftUI

struct OperProgressSettingsView: View {
    @Binding var config: OperProgressConfiguration

    @EnvironmentObject private var viewModel: MAAViewModel

    /// 干员搜索框内容。
    @State private var searchText = ""
    /// 当前选中的干员（「添加」按钮的目标）。
    @State private var selectedOperator: OperProgressOperator?
    /// 选中后收起建议列表；再次编辑搜索文本时恢复。
    @State private var suggestionsDismissed = false
    /// 展开的卡片集合（「全部折叠」与删除时同步清理）。
    @State private var expandedPlans: Set<UUID> = []

    private static let toolboxURL = URL(string: "https://arkntools.app/#/material")!
    private var directory: OperProgressOperatorDirectory.Directory { OperProgressOperatorDirectory.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Link("在明日方舟工具箱中在线编辑计划", destination: Self.toolboxURL)
                    .font(.callout)

                actionButtons
                    .frame(maxWidth: .infinity)

                operatorPicker

                planList
            }
            .padding()
        }
    }

    // MARK: - 操作按钮行

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button("全部折叠") {
                expandedPlans.removeAll()
            }
            Button("清空") {
                config.plans.removeAll()
                expandedPlans.removeAll()
            }
            Button("解析剪贴板") {
                parseClipboard()
            }
        }
    }

    // MARK: - 干员选择

    private var operatorPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("搜索干员", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { _, newValue in
                        if newValue != selectedOperator?.selectionTitle {
                            selectedOperator = nil
                            suggestionsDismissed = false
                        }
                    }
                Button("添加") {
                    addOperator()
                }
                .disabled(selectedOperator == nil)
            }

            if !matches.isEmpty {
                suggestionList
            }
        }
    }

    private var matches: [OperProgressOperator] {
        guard !suggestionsDismissed else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return directory.all.filter {
            $0.selectionTitle.localizedCaseInsensitiveContains(query) || $0.name.contains(query)
        }
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(matches) { oper in
                    Button {
                        select(oper)
                    } label: {
                        HStack(spacing: 6) {
                            OperProgressAvatar(id: oper.id, size: 16)
                            Text(oper.selectionTitle)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(CGFloat(matches.count) * 24 + 8, 200))
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }

    /// 选中干员：补全搜索框、收起建议列表。
    private func select(_ oper: OperProgressOperator) {
        selectedOperator = oper
        searchText = oper.selectionTitle
        suggestionsDismissed = true
    }

    /// 添加默认目标：精英化 2、技能 7 级、三技能专 3，新卡片自动展开。
    private func addOperator() {
        guard let oper = selectedOperator else { return }
        let plan = OperProgressPlan(
            role: oper.role, name: oper.name,
            elite: 2, skillLevel: 7, skillMastery: [3, 3, 3])
        config.plans.append(plan)
        expandedPlans.insert(plan.id)
    }

    // MARK: - 计划列表

    @ViewBuilder private var planList: some View {
        if config.plans.isEmpty {
            Text("尚未添加干员，搜索选择后设置目标")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($config.plans) { $plan in
                    let index = config.plans.firstIndex { $0.id == plan.id } ?? 0
                    OperProgressPlanCard(
                        plan: $plan,
                        isExpanded: expansionBinding(for: plan.id),
                        index: index,
                        skillCount: skillCount(for: plan),
                        displayName: displayName(for: plan),
                        avatarID: operatorID(for: plan),
                        onDelete: { removePlan(plan) })
                }
            }
            // 运行中列表不可编辑（对齐 WPF：任务运行时 ListBox 不响应交互）。
            .disabled(viewModel.status != .idle)
        }
    }

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding {
            expandedPlans.contains(id)
        } set: { isExpanded in
            if isExpanded {
                expandedPlans.insert(id)
            } else {
                expandedPlans.remove(id)
            }
        }
    }

    private func removePlan(_ plan: OperProgressPlan) {
        config.plans.removeAll { $0.id == plan.id }
        expandedPlans.remove(plan.id)
    }

    private func skillCount(for plan: OperProgressPlan) -> Int {
        directory.findOperator(named: plan.name, role: plan.role)?.skillCount ?? 3
    }

    private func displayName(for plan: OperProgressPlan) -> String {
        directory.findOperator(named: plan.name, role: plan.role)?.displayName ?? plan.name
    }

    private func operatorID(for plan: OperProgressPlan) -> String? {
        directory.findOperator(named: plan.name, role: plan.role)?.id
    }

    // MARK: - 解析剪贴板

    private func parseClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            viewModel.logError(verbatim: "解析失败\n剪贴板没有文本")
            return
        }
        do {
            let plans = try OperProgressPlanParser.parse(text)
            config.plans.append(contentsOf: plans)
            viewModel.logInfo(verbatim: "解析成功，添加 \(plans.count) 条计划")
        } catch {
            viewModel.logError(verbatim: "解析失败\n\(error.localizedDescription)")
        }
    }
}

// MARK: - 计划卡片

/// 单条培养计划卡片：折叠头部（序号/头像/显示名/目标摘要/删除）+ 展开编辑区（五行目标）。
private struct OperProgressPlanCard: View {
    @Binding var plan: OperProgressPlan
    @Binding var isExpanded: Bool

    let index: Int
    let skillCount: Int
    let displayName: String
    let avatarID: String?
    let onDelete: () -> Void

    // 编辑态：勾选与目标值分开存放（对齐 WPF 条目 VM——取消勾选只把写回值归零，
    // 目标值在卡片存续期间保留，重新勾选即恢复）。
    @State private var eliteEnabled: Bool
    @State private var eliteValue: Int
    @State private var levelEnabled: Bool
    @State private var levelValue: Int
    @State private var masteryEnabled: [Bool]
    @State private var masteryValues: [Int]

    init(
        plan: Binding<OperProgressPlan>,
        isExpanded: Binding<Bool>,
        index: Int,
        skillCount: Int,
        displayName: String,
        avatarID: String?,
        onDelete: @escaping () -> Void
    ) {
        self._plan = plan
        self._isExpanded = isExpanded
        self.index = index
        self.skillCount = skillCount
        self.displayName = displayName
        self.avatarID = avatarID
        self.onDelete = onDelete

        let value = plan.wrappedValue
        let mastery = (0..<3).map { value.skillMastery.indices.contains($0) ? value.skillMastery[$0] : 0 }
        _eliteEnabled = State(initialValue: value.elite > 0)
        _eliteValue = State(initialValue: value.elite > 0 ? value.elite : 2)
        _levelEnabled = State(initialValue: value.skillLevel > 0)
        _levelValue = State(initialValue: value.skillLevel > 0 ? value.skillLevel : 7)
        _masteryEnabled = State(initialValue: mastery.map { $0 > 0 })
        _masteryValues = State(initialValue: mastery.map { $0 > 0 ? $0 : 3 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider()
                    .padding(.top, 8)
                editor
            }
        }
        .padding(8)
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("\(index + 1)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    OperProgressAvatar(id: avatarID, size: 18)
                    Text(displayName)
                    targetSummary
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("删除")
        }
    }

    @ViewBuilder private var targetSummary: some View {
        if plan.elite > 0 {
            badge("精英\(plan.elite)")
        }
        if plan.skillLevel > 0 {
            badge("技能\(plan.skillLevel)")
        }
        ForEach(0..<3, id: \.self) { skill in
            if skill < skillCount, masteryValue(skill) > 0 {
                badge("技能\(skill + 1)专\(plan.skillMastery[skill])")
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    private func masteryValue(_ skill: Int) -> Int {
        plan.skillMastery.indices.contains(skill) ? plan.skillMastery[skill] : 0
    }

    // MARK: 编辑区

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            pickerRow(
                label: "精英化",
                isOn: Binding(get: { eliteEnabled }, set: { setEliteEnabled($0) }),
                value: Binding(get: { eliteValue }, set: { setEliteValue($0) }),
                options: [(value: 0, label: "---"), (value: 1, label: "1"), (value: 2, label: "2")])

            pickerRow(
                label: "技能基础等级",
                isOn: Binding(get: { levelEnabled }, set: { setLevelEnabled($0) }),
                value: Binding(get: { levelValue }, set: { setLevelValue($0) }),
                options: [(value: 0, label: "---")]
                    + (2...7).map { (value: $0, label: "Lv. \($0)") })

            ForEach(0..<3, id: \.self) { skill in
                masteryRow(skill)
            }
        }
        .padding(.top, 8)
    }

    private func pickerRow(
        label: LocalizedStringKey,
        isOn: Binding<Bool>,
        value: Binding<Int>,
        options: [(value: Int, label: String)]
    ) -> some View {
        HStack(spacing: 8) {
            Toggle(label, isOn: isOn)
                .toggleStyle(.checkbox)
                .frame(minWidth: 110, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: value) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            Spacer()
        }
    }

    /// 专精行：标签「技能 N」，超出干员技能数的行整体禁用。
    private func masteryRow(_ skill: Int) -> some View {
        let rowEnabled = skill < skillCount
        return HStack(spacing: 8) {
            Toggle(
                "技能 \(skill + 1)",
                isOn: Binding(
                    get: { rowEnabled && masteryEnabled[skill] },
                    set: { setMasteryEnabled(skill, $0) })
            )
            .toggleStyle(.checkbox)
            .frame(minWidth: 110, alignment: .leading)
            .disabled(!rowEnabled)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "",
                selection: Binding(
                    get: { masteryValues[skill] },
                    set: { setMasteryValue(skill, $0) })
            ) {
                Text("---").tag(0)
                Text("专精 1").tag(1)
                Text("专精 2").tag(2)
                Text("专精 3").tag(3)
            }
            .labelsHidden()
            .frame(width: 110)
            .disabled(!rowEnabled)
            Spacer()
        }
    }

    // MARK: 编辑规则（对齐 WPF OperProgressPlanItemViewModel）

    private func setEliteEnabled(_ on: Bool) {
        if on && eliteValue == 0 {
            eliteValue = 2
        }
        eliteEnabled = on
        writeBack()
    }

    private func setEliteValue(_ value: Int) {
        eliteValue = value
        eliteEnabled = value > 0
        writeBack()
    }

    private func setLevelEnabled(_ on: Bool) {
        if on && levelValue == 0 {
            levelValue = 7
        }
        levelEnabled = on
        writeBack()
    }

    private func setLevelValue(_ value: Int) {
        levelValue = value
        levelEnabled = value > 0
        // 专精前置为 7 级：设定 2–6 级目标时专精不共存，清空三行专精（值保留，重新勾选可恢复）。
        if value > 0 && value < 7 {
            for skill in 0..<3 {
                masteryEnabled[skill] = false
            }
        }
        writeBack()
    }

    private func setMasteryEnabled(_ skill: Int, _ on: Bool) {
        if on && masteryValues[skill] == 0 {
            // 勾选且未选档位：自动设为专 3（经 setMasteryValue 走补足等级的规则）。
            setMasteryValue(skill, 3)
            return
        }
        masteryEnabled[skill] = on
        writeBack()
    }

    private func setMasteryValue(_ skill: Int, _ value: Int) {
        masteryValues[skill] = value
        masteryEnabled[skill] = value > 0
        // 设专精且已有技能等级目标：自动补至 7 级（等级未设定时保持不设定）。
        if value > 0 && levelValue != 0 {
            levelValue = 7
            levelEnabled = true
        }
        writeBack()
    }

    /// 取消勾选 = 该维度目标归 0（写回配置时不带该键）；超出技能数的专精行不参与写回。
    private func writeBack() {
        plan.elite = eliteEnabled ? eliteValue : 0
        plan.skillLevel = levelEnabled ? levelValue : 0
        plan.skillMastery = (0..<3).map { skill in
            (masteryEnabled[skill] && skill < skillCount) ? masteryValues[skill] : 0
        }
    }
}

// MARK: - 头像

private struct OperProgressAvatar: View {
    let id: String?
    var size: CGFloat = 18

    var body: some View {
        if let id, let image = OperProgressAvatarCache.shared.image(for: id) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "person.crop.square")
                        .font(.system(size: size * 0.7))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

/// 头像磁盘加载缓存；加载失败记入 missing，后续直接走占位图。
@MainActor
private final class OperProgressAvatarCache {
    static let shared = OperProgressAvatarCache()

    private var images: [String: NSImage] = [:]
    private var missing: Set<String> = []

    func image(for id: String) -> NSImage? {
        if let image = images[id] {
            return image
        }
        if missing.contains(id) {
            return nil
        }
        let image = OperProgressOperatorDirectory.shared.avatarURL(for: id)
            .flatMap { NSImage(contentsOf: $0) }
        if let image {
            images[id] = image
        } else {
            missing.insert(id)
        }
        return image
    }
}

struct OperProgressSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        OperProgressSettingsView(config: .constant(.init()))
            .environmentObject(MAAViewModel())
    }
}
