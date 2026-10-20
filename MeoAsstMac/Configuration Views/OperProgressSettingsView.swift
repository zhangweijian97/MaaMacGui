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
    /// 搜索框聚焦态：聚焦即展开建议列表（对齐 WPF ComboBox 点开即浏览全量）。
    @FocusState private var pickerFocused: Bool
    /// 展开的卡片集合（「全部折叠」与删除时同步清理）。
    @State private var expandedPlans: Set<UUID> = []

    private static let toolboxURL = URL(string: "https://arkntools.app/#/material")!

    /// 干员目录持有为视图状态：系统语言切换时重载，刷新显示名/下拉列表的本地化
    /// （对齐 WPF `LocalizationHelper.LanguageChanged += RefreshPlanItemLocalization`；
    /// 我方无应用内语言设置，观察 `NSLocale.currentLocaleDidChangeNotification`）。
    @State private var directory = OperProgressOperatorDirectory.shared
    @State private var directoryLanguage: String?

    private func reloadDirectoryIfNeeded(force: Bool = false) {
        let language = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        guard force || directoryLanguage != language else { return }
        directory = OperProgressOperatorDirectory.Directory.load()
        directoryLanguage = language
    }

    var body: some View {
        // 虚拟化 + 固定区吸顶（对齐 WPF：链接随外层面板滚动，按钮行与干员选择固定，
        // 列表惰性实例化——LazyVStack + Section header 吸顶）。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                Link("在明日方舟工具箱中在线编辑计划", destination: Self.toolboxURL)
                    .font(.callout)

                Section {
                    planList
                } header: {
                    VStack(spacing: 12) {
                        actionButtons
                            .frame(maxWidth: .infinity)

                        operatorPicker
                    }
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .padding()
        }
        // 失焦收起下拉（走查#3，goal-cbe1e6）——下拉显隐本就绑定 pickerFocused，
        // 这里补两条标准 macOS 失焦路径：① ESC 经 onExitCommand 退出焦点；
        // ② 点空白经容器点击层退出焦点（交互控件各自消费点击，不经过此层，
        // 已验收的「点开即浏览全量 / 选中后收起显示头像」不受影响）。
        .contentShape(Rectangle())
        .onTapGesture {
            if pickerFocused {
                pickerFocused = false
            }
        }
        .onExitCommand {
            if pickerFocused {
                pickerFocused = false
            }
        }
        .onAppear {
            reloadDirectoryIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            reloadDirectoryIfNeeded(force: true)
        }
        // Summary 回调消费后整体重建（对齐 WPF RefreshUI 语义：卡片/展开态/滚动位置重置，
        // 从写回后的配置重建编辑态）
        .id(viewModel.operProgressRefreshToken)
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

    /// 点开（聚焦）即浏览全量干员，输入即时过滤；选中后收起建议并在框内左侧
    /// 显示已选干员头像（对齐 WPF 可搜索 ComboBox：DropDownOpened 清过滤展示全量
    /// xaml:70-104 + 收起态头像浮层贴框内左侧）。
    private var operatorPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                operatorField
                Button("添加") {
                    addOperator()
                }
                .disabled(selectedOperator == nil)
            }

            if pickerFocused, !matches.isEmpty {
                suggestionList
            }
        }
    }

    private var operatorField: some View {
        HStack(spacing: 6) {
            if let oper = selectedOperator {
                OperProgressAvatar(id: oper.id, size: 16)
            }
            TextField("搜索干员", text: $searchText)
                .textFieldStyle(.plain)
                .focused($pickerFocused)
                .onChange(of: searchText) { _, newValue in
                    if newValue != selectedOperator?.selectionTitle {
                        selectedOperator = nil
                        suggestionsDismissed = false
                    }
                }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(pickerFocused ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 1)
        )
    }

    private var matches: [OperProgressOperator] {
        guard !suggestionsDismissed else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        // 空查询即全量浏览（对齐 WPF：点开下拉展示完整列表，非必须先输入）
        guard !query.isEmpty else { return directory.all }
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
        .frame(height: min(CGFloat(matches.count) * 24 + 8, 240))
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

    /// 卡片作为 Section 内容直接挂在 LazyVStack 上（惰性实例化）；不套全量容器。
    @ViewBuilder private var planList: some View {
        if config.plans.isEmpty {
            Text("尚未添加干员，搜索选择后设置目标")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            // 运行中列表不可编辑（对齐 WPF：任务运行时 ListBox 不响应交互）。
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

    // 编辑态：互斥规则住在纯逻辑模型里（goal-0729d7 可测性抽取），卡片只做呈现与转发。
    @State private var editor: OperProgressPlanEditor
    /// 头部悬停态：仅驱动删除按钮显隐（WPF 正本 xaml:299-324——IsMouseOver 触发器只挂删除按钮自身，徽标区常驻无悬停触发器）。
    @State private var isHovered = false

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

        _editor = State(initialValue: OperProgressPlanEditor(plan: plan.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider()
                    .padding(.top, 8)
                editorSection
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
                    // 尾部预留位：悬停浮现的删除按钮落在此区，不覆盖徽标（参照 WPF 删除按钮住独立 25pt Grid.Column 预留位）。
                    Color.clear
                        .frame(width: 25, height: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // overlay 设计前提：浮现时恒最上层（走查#2，goal-cbe1e6）——显式 zIndex 抬升
            // 删除按钮及其悬浮容器，高于同层徽标区/文本区（默认 0），不依赖布局预留位巧合。
            .overlay(alignment: .trailing) {
                if isHovered {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                    .zIndex(1)
                }
            }
            .zIndex(1)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    /// 目标摘要：精英化角标图 / 技能等级四角框 / 专精三圆角标+技能序号
    /// （对齐 WPF xaml:194-298 的三处图形；等级框与专精图标互斥显隐——
    /// 等级框仅在「设定等级且无任何专精」时显示）。
    @ViewBuilder private var targetSummary: some View {
        if plan.elite > 0 {
            eliteIcon(plan.elite)
        }
        if plan.skillLevel > 0, plan.skillMastery.allSatisfy({ $0 <= 0 }) {
            skillLevelFrame(plan.skillLevel)
        }
        ForEach(0..<3, id: \.self) { skill in
            if skill < skillCount, masteryValue(skill) > 0 {
                masteryBadge(skill)
            }
        }
    }

    /// 精英化角标：上游 WPF 同款 Elite_N.png（40×30/40×38），16 高等比 + 轻投影。
    private func eliteIcon(_ elite: Int) -> some View {
        Image("OperElite\(elite)")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .shadow(color: .black.opacity(0.8), radius: 4, y: 0.5)
    }

    /// 技能等级四角框：48 设计稿的角括号等比缩到 16×16，中心数字
    /// （对齐 WPF Path Data M 0,14 L 0,0 L 14,0 …，Stroke=PrimaryTextBrush 1.5、方头端点）。
    private func skillLevelFrame(_ level: Int) -> some View {
        ZStack {
            CornerBracketShape()
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter))
            Text("\(level)")
                .font(.system(size: 12))
                .foregroundStyle(.primary)
        }
        .frame(width: 16, height: 16)
    }

    /// 专精角标：品字三圆按等级点亮 + 右上技能序号（对齐 WPF SkillSpecializationIcon + TextBlock）。
    private func masteryBadge(_ skill: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            OperProgressMasteryIcon(level: masteryValue(skill), size: 16)
            Text("\(skill + 1)")
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 0.5)
        }
        .fixedSize()
    }

    private func masteryValue(_ skill: Int) -> Int {
        plan.skillMastery.indices.contains(skill) ? plan.skillMastery[skill] : 0
    }

    // MARK: 编辑区

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            pickerRow(
                label: "精英化",
                isOn: Binding(get: { editor.eliteEnabled }, set: { setEliteEnabled($0) }),
                value: Binding(get: { editor.eliteValue }, set: { setEliteValue($0) }),
                options: [(value: 0, label: "---"), (value: 1, label: "1"), (value: 2, label: "2")])

            pickerRow(
                label: "技能基础等级",
                isOn: Binding(get: { editor.levelEnabled }, set: { setLevelEnabled($0) }),
                value: Binding(get: { editor.levelValue }, set: { setLevelValue($0) }),
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
                    get: { rowEnabled && editor.masteryEnabled[skill] },
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
                    get: { editor.masteryValues[skill] },
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

    // MARK: 编辑规则（互斥规则住 OperProgressPlanEditor，此处只转发）

    private func setEliteEnabled(_ on: Bool) {
        editor.setEliteEnabled(on)
        writeBack()
    }

    private func setEliteValue(_ value: Int) {
        editor.setEliteValue(value)
        writeBack()
    }

    private func setLevelEnabled(_ on: Bool) {
        editor.setLevelEnabled(on)
        writeBack()
    }

    private func setLevelValue(_ value: Int) {
        editor.setLevelValue(value)
        writeBack()
    }

    private func setMasteryEnabled(_ skill: Int, _ on: Bool) {
        editor.setMasteryEnabled(skill, on)
        writeBack()
    }

    private func setMasteryValue(_ skill: Int, _ value: Int) {
        editor.setMasteryValue(skill, value)
        writeBack()
    }

    /// 写回配置：取消勾选 = 该维度目标归 0（不带该键）；超出技能数的专精行不参与写回。
    private func writeBack() {
        editor.writeBack(into: &plan, skillCount: skillCount)
    }
}

// MARK: - 目标摘要图形

/// 技能等级四角框：角括号描边（对齐 WPF 48×48 设计稿 Path 的等比缩放——
/// 括号臂长 14/48 ≈ 宽度 29%，线宽按绝对像素 1.5 不随缩放）。
private struct CornerBracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = min(rect.width, rect.height) * (14.0 / 48.0)
        // 左上
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // 右上
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // 左下
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        // 右下
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        return path
    }
}

/// 专精等级角标：品字排布三圆点，按专精等级逐步点亮——专 1 亮上圆、专 2 加亮右下圆、
/// 专 3 全亮（对齐 WPF SkillSpecializationIcon：11×11 设计稿坐标固定、等比缩放、
/// 亮 #FFFFFF / 灭 #555555、轻投影）。
private struct OperProgressMasteryIcon: View {
    let level: Int
    var size: CGFloat = 16

    var body: some View {
        let scale = size / 11
        let dot = 4 * scale
        return ZStack {
            Circle()
                .fill(Self.color(on: level >= 1))
                .frame(width: dot, height: dot)
                .position(x: (3.6 + 2) * scale, y: (1 + 2) * scale)
            Circle()
                .fill(Self.color(on: level >= 2))
                .frame(width: dot, height: dot)
                .position(x: (6 + 2) * scale, y: (6 + 2) * scale)
            Circle()
                .fill(Self.color(on: level >= 3))
                .frame(width: dot, height: dot)
                .position(x: (0.8 + 2) * scale, y: (6 + 2) * scale)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
    }

    private static func color(on: Bool) -> Color {
        on ? .white : Color(red: 0x55 / 255.0, green: 0x55 / 255.0, blue: 0x55 / 255.0)
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
