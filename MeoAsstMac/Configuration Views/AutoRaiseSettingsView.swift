//
//  AutoRaiseSettingsView.swift
//  MeoAsstMac
//

import SwiftUI

struct AutoRaiseSettingsView: View {
    @Environment(NewViewModel.self) private var viewModel
    /// 浮层实底用固定色：系统动态色在 vibrant 上下文会解析出半透明变体（用户截图实证文字穿透）。
    @Environment(\.colorScheme) private var colorScheme

    @Binding var config: AutoRaiseConfiguration

    @State private var itemNames = [String: String]()
    @State private var nameTaskToken: UUID?

    /// 干员搜索框内容。
    @State private var searchText = ""
    /// 当前展开目标设置面板的干员。
    @State private var panelName: String?
    /// 目标设置面板的草稿值（添加/更新时写回计划）。
    @State private var draft = AutoRaiseGoalDraft()
    /// 选中干员后关闭建议浮层（全名仍会命中自身匹配，不关会常驻遮挡面板顶部）。
    @State private var suggestionsDismissed = false
    /// 建议行高，随系统字体缩放。
    @ScaledMetric(relativeTo: .body) private var suggestionRowHeight: CGFloat = 24
    /// 建议浮层顶部偏移：输入框高度 + 间隙，让列表从输入框下方展开不盖输入框。
    @ScaledMetric(relativeTo: .body) private var suggestionListTopOffset: CGFloat = 30
    /// 键盘 ↑/↓ 在建议列表中的高亮下标（循环回绕）。
    @State private var selectedIndex = 0
    /// 悬停中的建议行（与键盘高亮共用行背景样式）。
    @State private var hoverName: String?
    /// 清空按钮悬停态。
    @State private var clearButtonHover = false

    /// 滚动锚点：目标面板顶部。
    private static let goalPanelAnchor = "auto-raise-goal-panel"

    private var plan: AutoRaisePlan {
        AutoRaisePlan(json: config.planJson)
    }

    private var demand: AutoRaiseDemand? {
        guard !plan.entries.isEmpty else { return nil }
        return plan.demand(in: AutoRaiseDemandTable.shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 搜索区钉顶：宿主链（MAADetail/TaskDetail）无人提供滚动容器，
            // 标题+搜索框留在滚动区外，建议浮层位置才不受下方内容展开影响。
            VStack(alignment: .leading, spacing: 12) {
                Text("养成计划")
                    .font(.headline)

                searchSection
            }
            .padding(.horizontal)
            .padding(.top)
            // 重新编辑搜索文本（与当前选中干员不一致）才恢复建议；
            // selectCharacter 里也会改 searchText，须避免把刚置的关闭态冲掉。
            .onChange(of: searchText) { _, newValue in
                if newValue != panelName {
                    suggestionsDismissed = false
                }
                selectedIndex = 0
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let panelName {
                            goalPanel(name: panelName)
                        }

                        planListSection

                        Divider()

                        debugSection

                        Divider()

                        Text("缺口报告")
                            .font(.headline)

                        gapReport
                    }
                    .padding()
                    // 小窗兜底：面板展开时滚到其顶部，保证完整进入视野。
                    .onChange(of: panelName) { _, newName in
                        guard newName != nil else { return }
                        withAnimation {
                            proxy.scrollTo(Self.goalPanelAnchor, anchor: .top)
                        }
                    }
                }
            }
        }
        .task(id: AutoRaiseReportKey(items: viewModel.depot?.items, plan: config.planJson)) {
            await updateItemNames()
        }
    }

    // MARK: - 干员搜索

    private var searchSection: some View {
        TextField(String(localized: "搜索干员（支持拼音）"), text: $searchText)
            .textFieldStyle(.roundedBorder)
            // ↑/↓ 循环移动高亮，Enter 选中，Esc 关浮层（已关则交还默认行为）。
            .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape]) { press in
                let matches = searchMatches
                guard !suggestionsDismissed, !matches.isEmpty else { return .ignored }
                switch press.key {
                case .upArrow:
                    selectedIndex = (selectedSuggestionIndex(matches) - 1 + matches.count) % matches.count
                    return .handled
                case .downArrow:
                    selectedIndex = (selectedSuggestionIndex(matches) + 1) % matches.count
                    return .handled
                case .return:
                    selectCharacter(matches[selectedSuggestionIndex(matches)])
                    return .handled
                case .escape:
                    suggestionsDismissed = true
                    return .handled
                default:
                    return .ignored
                }
            }
            // 快速清空：占输入框右侧留出的 22pt 空隙，不压文字。
            .overlay(alignment: .trailing) {
                clearSearchButton
                    .padding(.trailing, 4)
            }
            .padding(.trailing, 22)
            // 建议列表是浮层：不占布局流，从输入框顶边下移一个输入框高度起向下展开，
            // 不会盖住输入框；zIndex 抬高保证盖过页面后续内容。
            .overlay(alignment: .top) {
                suggestionList
                    .offset(y: suggestionListTopOffset)
            }
            .zIndex(1)
    }

    /// 清空按钮：输入非空才显示；点击清搜索文本、收起面板（浮层随空匹配自然消失）。
    @ViewBuilder private var clearSearchButton: some View {
        if !searchText.isEmpty {
            Button {
                searchText = ""
                panelName = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(clearButtonHover ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { clearButtonHover = $0 }
        }
    }

    /// 键盘高亮下标钳制在当前匹配范围内。
    private func selectedSuggestionIndex(_ matches: [String]) -> Int {
        guard !matches.isEmpty else { return 0 }
        return min(selectedIndex, matches.count - 1)
    }

    /// 匹配结果浮层：选中后关闭、重新编辑恢复；最多 30 条。
    /// 高度显式 = 行数×行高封顶 200：overlay 只向子视图提议宿主（输入框）尺寸，
    /// 仅用 maxHeight 会被压成单行视口，第二条起不可见。
    @ViewBuilder private var suggestionList: some View {
        let matches = searchMatches
        if !matches.isEmpty, !suggestionsDismissed {
            let listHeight = min(CGFloat(matches.count) * suggestionRowHeight, 200)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element) { index, name in
                        Button {
                            selectCharacter(name)
                        } label: {
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: suggestionRowHeight)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                                .background(
                                    hoverName == name || index == selectedSuggestionIndex(matches)
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoverName = hovering ? name : nil
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: listHeight)
            // 实底必须用固定色：系统动态色（control/textBackground）在此上下文解析出半透明变体（用户截图实证文字穿透）。
            .background(colorScheme == .dark ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
            }
            .shadow(radius: 4)
        }
    }

    /// 匹配结果（中文名子串 / 全拼片段 / 首字母前缀），按名称排序取前 30。
    private var searchMatches: [String] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return Array(AutoRaiseSearchIndex.matching(query).sorted().prefix(30))
    }

    /// 选中干员：输入框补全全名，关闭建议浮层，展开目标面板（已在计划中则回填现值）。
    private func selectCharacter(_ name: String) {
        panelName = name
        searchText = name
        suggestionsDismissed = true
        let entries = plan.entries.filter { $0.name == name }
        draft = AutoRaiseGoalDraft(entries: entries)
    }

    // MARK: - 目标设置面板（布局对照明日方舟工具箱的养成计划弹窗）

    private func goalPanel(name: String) -> some View {
        let tableCharacter = AutoRaiseDemandTable.shared[name]
        let inPlan = plan.entries.contains { $0.name == name }
        return VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)

            eliteSection(tableCharacter)
            skillsSection(tableCharacter)
            masterySection(tableCharacter)

            if tableCharacter == nil {
                Text("需求表无此干员，无法设置养成目标")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(inPlan ? String(localized: "更新") : String(localized: "添加")) {
                    commitDraft()
                }
                .disabled(tableCharacter == nil)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
        }
        .id(Self.goalPanelAnchor)
    }

    @ViewBuilder private func eliteSection(_ character: AutoRaiseCharacterDemand?) -> some View {
        let available = character?.elite != nil
        HStack(spacing: 16) {
            Toggle("精英化 1", isOn: eliteBinding(target: 1))
                .disabled(!available)
            Toggle("精英化 2", isOn: eliteBinding(target: 2))
                .disabled(!available || (character?.elite?.count ?? 0) < 2)
        }
    }

    /// 勾选状态 = 目标阶 ≥ N（勾 2 隐含勾 1；取消 1 连带取消 2）。
    private func eliteBinding(target: Int) -> Binding<Bool> {
        Binding {
            draft.eliteTarget >= target
        } set: { isOn in
            if isOn {
                draft.eliteTarget = max(draft.eliteTarget, target)
            } else if draft.eliteTarget >= target {
                draft.eliteTarget = target - 1
            }
        }
    }

    @ViewBuilder private func skillsSection(_ character: AutoRaiseCharacterDemand?) -> some View {
        // skills 增量阶数（6 = 等级 1-7）；无数据则整行禁用，选项退化为静态区间。
        let hasData = !(character?.skills ?? []).isEmpty
        let maxLevel = hasData ? min((character?.skills?.count ?? 0) + 1, 7) : 0
        // 选项恒为合法闭区间（lower ≤ upper），禁用态也不崩。
        let fromOptions = hasData ? Array(1...max(1, min(maxLevel - 1, 6))) : Array(1...6)
        let toUpper = hasData ? maxLevel : 7
        let toOptions = Array((draft.skills.from + 1)...max(draft.skills.from + 1, toUpper))
        HStack(spacing: 8) {
            Toggle("技能", isOn: $draft.skills.isEnabled)
                .disabled(!hasData)
            Text("从")
            Picker(String(localized: "技能起始等级"), selection: skillsFromBinding) {
                ForEach(fromOptions, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 64)
            .disabled(!hasData)
            Text("到")
            Picker(String(localized: "技能目标等级"), selection: skillsToBinding(toUpper: toUpper)) {
                ForEach(toOptions, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 64)
            .disabled(!hasData)
        }
    }

    /// 改起始等级即视为启用该目标，并把目标等级抬到至少 +1（from < to 结构保证）。
    private var skillsFromBinding: Binding<Int> {
        Binding {
            draft.skills.from
        } set: { newValue in
            draft.skills.isEnabled = true
            draft.skills.from = newValue
            if draft.skills.to <= newValue {
                draft.skills.to = min(newValue + 1, 7)
            }
        }
    }

    private func skillsToBinding(toUpper: Int) -> Binding<Int> {
        Binding {
            max(draft.skills.to, draft.skills.from + 1)
        } set: { newValue in
            draft.skills.isEnabled = true
            draft.skills.to = min(max(newValue, draft.skills.from + 1), max(2, toUpper))
        }
    }

    @ViewBuilder private func masterySection(_ character: AutoRaiseCharacterDemand?) -> some View {
        let slots = character?.mastery ?? []
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                masteryRow(
                    index: index,
                    slotAvailable: index < slots.count && slots[index] != nil,
                    label: character?.skillLabel(index + 1) ?? masteryName(index)
                )
            }
        }
    }

    private func masteryRow(index: Int, slotAvailable: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            Toggle(label, isOn: masteryEnabledBinding(index: index))
                .disabled(!slotAvailable)
            Text("从")
            Picker(String(localized: "专精起始档位"), selection: masteryFromBinding(index: index)) {
                ForEach(0...2, id: \.self) { rank in
                    Text("\(rank)").tag(rank)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 64)
            .disabled(!slotAvailable)
            Text("到")
            Picker(String(localized: "专精目标档位"), selection: masteryToBinding(index: index)) {
                ForEach((draft.masteries[index].from + 1)...3, id: \.self) { rank in
                    Text("\(rank)").tag(rank)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 64)
            .disabled(!slotAvailable)
        }
    }

    private func masteryName(_ index: Int) -> String {
        [String(localized: "一技能"), String(localized: "二技能"), String(localized: "三技能")][index]
    }

    /// 改起始档位即视为启用该目标，并把目标档位抬到至少 +1（from < to 结构保证）。
    private func masteryFromBinding(index: Int) -> Binding<Int> {
        Binding {
            draft.masteries[index].from
        } set: { newValue in
            draft.masteries[index].isEnabled = true
            draft.masteries[index].from = newValue
            if draft.masteries[index].to <= newValue {
                draft.masteries[index].to = min(newValue + 1, 3)
            }
        }
    }

    private func masteryToBinding(index: Int) -> Binding<Int> {
        Binding {
            max(draft.masteries[index].to, draft.masteries[index].from + 1)
        } set: { newValue in
            draft.masteries[index].isEnabled = true
            draft.masteries[index].to = max(newValue, draft.masteries[index].from + 1)
        }
    }

    private func masteryEnabledBinding(index: Int) -> Binding<Bool> {
        Binding {
            draft.masteries[index].isEnabled
        } set: { isOn in
            draft.masteries[index].isEnabled = isOn
        }
    }

    // MARK: - 待养成列表（按干员分组）

    private var planListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待养成")
                .font(.subheadline)

            let grouped = Dictionary(grouping: plan.entries, by: \.name)
            if grouped.isEmpty {
                Text("尚未添加干员，搜索选择后设置目标")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(grouped.keys.sorted(), id: \.self) { name in
                        characterGroup(name: name, entries: grouped[name]!.sorted(by: entryOrder))
                    }
                }
            }
        }
    }

    /// 组内排序：精英化 → 技能 → 专精（按技能序号）。
    private func entryOrder(_ lhs: AutoRaisePlan.Entry, _ rhs: AutoRaisePlan.Entry) -> Bool {
        switch (lhs.action, rhs.action) {
        case (.elite, .elite):
            return false
        case (.elite, _):
            return true
        case (_, .elite):
            return false
        case (.skills, .skills):
            return false
        case (.skills, _):
            return true
        case (_, .skills):
            return false
        case (.mastery, .mastery):
            return (lhs.skill ?? 0) < (rhs.skill ?? 0)
        }
    }

    private func characterGroup(name: String, entries: [AutoRaisePlan.Entry]) -> some View {
        let character = AutoRaiseDemandTable.shared[name]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    selectCharacter(name)
                } label: {
                    Text(name)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    removeCharacter(name)
                } label: {
                    Text("删除")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }
            ForEach(entries, id: \.self) { entry in
                HStack {
                    Text(entry.summaryText(character: character))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                    Spacer()
                    Button {
                        removeEntry(entry)
                    } label: {
                        Text("删除")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - 计划读写

    /// 以表单草稿替换该干员的全部计划条目，回写规范化 JSON。
    /// 需求表无数据的维度不写入（面板对应行本就禁用，此处兜底防手改 JSON 残留勾选）。
    private func commitDraft() {
        guard let name = panelName else { return }
        let tableCharacter = AutoRaiseDemandTable.shared[name]
        updatePlan { parsed in
            parsed.entries.removeAll { $0.name == name }
            if draft.eliteTarget > 0, tableCharacter?.elite != nil {
                parsed.entries.append(.init(name: name, action: .elite, from: 0, to: draft.eliteTarget, skill: nil))
            }
            if draft.skills.isEnabled, tableCharacter?.skills != nil {
                parsed.entries.append(.init(name: name, action: .skills, from: draft.skills.from, to: draft.skills.to, skill: nil))
            }
            let slots = tableCharacter?.mastery ?? []
            for (index, line) in draft.masteries.enumerated() where line.isEnabled {
                guard index < slots.count, slots[index] != nil else { continue }
                parsed.entries.append(.init(name: name, action: .mastery, from: line.from, to: line.to, skill: index + 1))
            }
        }
    }

    private func removeCharacter(_ name: String) {
        updatePlan { $0.entries.removeAll { $0.name == name } }
        if panelName == name {
            panelName = nil
        }
    }

    private func removeEntry(_ entry: AutoRaisePlan.Entry) {
        updatePlan { $0.entries.removeAll { $0.lineKey == entry.lineKey } }
    }

    private func updatePlan(_ transform: (inout AutoRaisePlan) -> Void) {
        var parsed = plan
        transform(&parsed)
        config.planJson = parsed.canonicalJson
    }

    // MARK: - 计划 JSON（debug 视图，最终用户界面不保留）

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("养成计划 JSON（debug）")
                .font(.subheadline)

            ScrollView {
                Text(debugJsonText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120)
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
            }

            planIssues
        }
    }

    /// 常态显示表单生成的规范化 JSON；手改坏 JSON 时原样展示原文便于排查。
    private var debugJsonText: String {
        let parsed = plan
        return parsed.isUnparseable ? config.planJson : parsed.canonicalJson
    }

    @ViewBuilder private var planIssues: some View {
        ForEach(plan.issues, id: \.self) { issue in
            Text(issue.message)
                .font(.callout)
                .foregroundStyle(.red)
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

/// 目标设置面板的草稿状态；一行 = 一个 from/to 区间 + 启用勾选。
private struct AutoRaiseGoalDraft: Hashable {
    struct Line: Hashable {
        var isEnabled = false
        var from: Int
        var to: Int
    }

    /// 精英化目标阶（0 = 不练，1/2 = 目标精英化阶）。
    var eliteTarget = 0
    /// 技能等级目标（1-7），默认 1 → 7。
    var skills = Line(from: 1, to: 7)
    /// 三行专精目标（0-3），下标 = 技能序号 − 1，默认 0 → 3。
    var masteries = [Line(from: 0, to: 3), Line(from: 0, to: 3), Line(from: 0, to: 3)]

    init() {}

    /// 从该干员已有计划条目回填（按钮呈「更新」态）。
    init(entries: [AutoRaisePlan.Entry]) {
        for entry in entries {
            switch entry.action {
            case .elite:
                eliteTarget = entry.to
            case .skills:
                skills = Line(isEnabled: true, from: entry.from, to: entry.to)
            case .mastery:
                if let skill = entry.skill, masteries.indices.contains(skill - 1) {
                    masteries[skill - 1] = Line(isEnabled: true, from: entry.from, to: entry.to)
                }
            }
        }
    }
}

/// 干员搜索索引：中文名 → 全拼 / 首字母（系统 toLatin 变换 + 去声调，惰性建立后缓存）。
private enum AutoRaiseSearchIndex {
    struct Entry {
        let fullPinyin: String
        let initials: String
    }

    static let entries: [String: Entry] = {
        var result = [String: Entry]()
        for name in AutoRaiseDemandTable.shared.keys {
            guard let latin = name.applyingTransform(.toLatin, reverse: false) else { continue }
            let syllables = latin.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            result[name] = Entry(
                fullPinyin: syllables.joined(),
                initials: syllables.compactMap(\.first).map(String.init).joined()
            )
        }
        return result
    }()

    /// 匹配规则：中文名子串 / 全拼片段 / 首字母前缀（如 lyyh → 凛御银灰）。
    static func matching(_ query: String) -> [String] {
        entries.filter { name, entry in
            name.lowercased().contains(query)
                || entry.fullPinyin.contains(query)
                || entry.initials.hasPrefix(query)
        }
        .map(\.key)
    }
}

/// 待养成行的行动短语。
private extension AutoRaisePlan.Entry {
    /// 专精短语优先查表显示技能真名（如「三技能（真银斩）专精 0 → 3」）；
    /// 干员无表条目时回退序号标签。
    func summaryText(character: AutoRaiseCharacterDemand?) -> String {
        switch action {
        case .elite:
            return String(localized: "精英化 → \(to)")
        case .skills:
            return String(localized: "技能 \(from) → \(to)")
        case .mastery:
            let label = character.map { $0.skillLabel(skill ?? 1) } ?? skillLabel
            return String(localized: "\(label)专精 \(from) → \(to)")
        }
    }

    var skillLabel: String {
        switch skill {
        case 1:
            return String(localized: "一技能")
        case 2:
            return String(localized: "二技能")
        case 3:
            return String(localized: "三技能")
        default:
            return String(localized: "第 \(skill ?? 0) 技能")
        }
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
