//
//  OperProgressSettingsView.swift
//  MeoAsstMac
//

import SwiftUI

/// 干员培养配置页：交互沿用自动养成表单（拼音搜索选干员 / 目标设置面板 / 待养成列表），
/// 输出模型换成协议口径的 `OperProgressPlanItem`——协议没有「当前等级（from）」，
/// 起止区间由 core 执行时现场识别。
struct OperProgressSettingsView: View {
    @Environment(NewViewModel.self) private var viewModel
    /// 浮层实底用固定色：系统动态色在 vibrant 上下文会解析出半透明变体（用户截图实证文字穿透）。
    @Environment(\.colorScheme) private var colorScheme

    @Binding var config: OperProgressConfiguration

    @State private var itemNames = [String: String]()
    @State private var nameTaskToken: UUID?

    /// 干员搜索框内容。
    @State private var searchText = ""
    /// 当前展开目标设置面板的干员。
    @State private var panelName: String?
    /// 目标设置面板的草稿值（添加/更新时写回计划）。
    @State private var draft = OperProgressGoalDraft()
    /// 选中干员后关闭建议浮层（全名仍会命中自身匹配，不关会常驻遮挡面板顶部）。
    @State private var suggestionsDismissed = false
    /// 建议行高，随系统字体缩放。
    @ScaledMetric(relativeTo: .body) private var suggestionRowHeight: CGFloat = 24
    /// 建议浮层顶部偏移：输入框高度 + 间隙，让列表从输入框下方展开不盖输入框。
    @ScaledMetric(relativeTo: .body) private var suggestionListTopOffset: CGFloat = 30
    /// 键盘 ↑/↓ 在建议列表中的高亮下标（循环回绕）；鼠标悬停同步到此（单一高亮源）。
    @State private var selectedIndex = 0
    /// 清空按钮悬停态。
    @State private var clearButtonHover = false

    /// 滚动锚点：目标面板顶部。
    private static let goalPanelAnchor = "oper-progress-goal-panel"

    /// 该干员在当前计划里的条目（面板回填与「更新/添加」按钮态）。
    private func planItem(name: String) -> OperProgressPlanItem? {
        config.plans.first { $0.name == name }
    }

    /// 计划的全量需求：协议不含当前等级（现场识别），按各线最低档起算
    /// （精英化 0 / 技能 1 级 / 专精 0），即实际所需不会超过该值。
    /// 累计逻辑借用自动养成骨架的 AutoRaisePlan（同一张需求表）。
    private var demand: AutoRaiseDemand? {
        guard !config.plans.isEmpty else { return nil }
        var plan = AutoRaisePlan(json: "[]")
        plan.entries = config.plans.flatMap(\.demandEntries)
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
            // 抬整层搜索区到滚动区之上：zIndex 只对直接父容器的兄弟生效，
            // 挂在 TextField 上盖不过滚动区（待养成画在浮层上，文字叠加）。
            .zIndex(1)
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

                        gapReportSection
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
        .task(id: OperProgressReportKey(items: viewModel.depot?.items, plans: config.plans)) {
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
            // 快速清空：✕ 在输入框内部右侧（同标准搜索框），不外占宽度。
            .overlay(alignment: .trailing) {
                clearSearchButton
                    .padding(.trailing, 4)
            }
            // 建议列表是浮层：不占布局流，从输入框顶边下移一个输入框高度起向下展开，
            // 不会盖住输入框（层序由外层搜索区的 zIndex 抬高）。
            // 缩进对齐滚动区内容：本区在滚动区外，滚动条占位实测 17，不缩会凸出。
            .padding(.trailing, 17)
            .overlay(alignment: .top) {
                suggestionList
                    .offset(y: suggestionListTopOffset)
                    .padding(.trailing, 17)
            }
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
                                    index == selectedSuggestionIndex(matches)
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            // 悬停即成为当前选中（单一高亮源，同系统菜单）。
                            if hovering { selectedIndex = index }
                        }
                    }
                }
            }
            // 隐藏 ScrollView 自带玻璃材质（macOS 26 默认，叠在实底上呈半透明）。
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity)
            .frame(height: listHeight)
            // 实底固定色 + ViewBuilder fill 形态（`in:` 变体疑似不渲染，像素实证穿透）。
            .background {
                RoundedRectangle(cornerRadius: 6).fill(colorScheme == .dark ? Color.black : Color.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
            }
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
        if let item = planItem(name: name) {
            draft = OperProgressGoalDraft(item: item)
        } else {
            draft = OperProgressGoalDraft()
        }
    }

    // MARK: - 目标设置面板

    private func goalPanel(name: String) -> some View {
        let tableCharacter = AutoRaiseDemandTable.shared[name]
        let inPlan = planItem(name: name) != nil
        return VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)

            roleSection()
            eliteSection()
            skillsSection
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

    /// 职业（协议 role）：同名干员分属不同职业时用于消歧；不设定则不下发该键。
    private func roleSection() -> some View {
        HStack(spacing: 8) {
            Text("职业")
            Picker(String(localized: "职业"), selection: $draft.role) {
                Text(String(localized: "不设定")).tag(OperProgressRole?.none)
                ForEach(OperProgressRole.allCases) { role in
                    Text(role.title).tag(OperProgressRole?.some(role))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
        }
    }

    /// 精英化目标：不练（不下发 elite 键）/ 精一 / 精二（协议只认 1|2）。
    /// 精一、精二选项按该干员可达档过滤（phaseMaxLevels 长度：3 档 = 全档、2 档 = 无精二、1 档 = 仅 E0）。
    private func eliteSection() -> some View {
        let phaseCount = min(max(AutoRaiseDemandTable.caps(for: panelName)?.count ?? 3, 1), 3)
        return HStack(spacing: 8) {
            Text("精英化")
            Picker(String(localized: "精英化"), selection: $draft.elite) {
                Text(String(localized: "不练")).tag(Int?.none)
                Text(String(localized: "精英化 1")).tag(Int?.some(1))
                    .disabled(phaseCount < 2)
                Text(String(localized: "精英化 2")).tag(Int?.some(2))
                    .disabled(phaseCount < 3)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
        }
    }

    /// 技能等级目标：不设定（不下发 skill_level 键）/ 2-7 级（协议区间，1 级是初始等级无需培养）。
    private var skillsSection: some View {
        HStack(spacing: 8) {
            Text("技能等级")
            Picker(String(localized: "技能等级"), selection: skillLevelBinding) {
                Text(String(localized: "不设定")).tag(0)
                ForEach(2...7, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
        }
    }

    /// 基础技能等级不足 7 级时清空专精目标（专精前置为 7 级，与 WPF 同口径）：
    /// 协议 skill_level 是单键，两种目标共存时只会下发其中一个。
    private var skillLevelBinding: Binding<Int> {
        Binding {
            draft.skillLevel
        } set: { newValue in
            draft.skillLevel = newValue
            if newValue > 0, newValue < 7 {
                draft.masteries = [.init(), .init(), .init()]
            }
        }
    }

    /// 三行专精目标：勾选 = 设定该技能专精（未勾选填 0 = 不专精）；无该技能（或该技能无专精数据）的行禁用。
    private func masterySection(_ character: AutoRaiseCharacterDemand?) -> some View {
        let slots = character?.mastery ?? []
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                masteryRow(
                    index: index,
                    slotAvailable: index < slots.count && slots[index] != nil,
                    label: character?.skillLabel(index + 1) ?? OperProgressGoalDraft.ordinalLabel(index)
                )
            }
        }
    }

    private func masteryRow(index: Int, slotAvailable: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            Toggle(label, isOn: masteryEnabledBinding(index: index))
                .disabled(!slotAvailable)
            Picker(String(localized: "专精目标档位"), selection: masteryRankBinding(index: index)) {
                ForEach(1...3, id: \.self) { rank in
                    Text("\(rank)").tag(rank)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 64)
            .disabled(!slotAvailable || !draft.masteries[index].isEnabled)
        }
    }

    /// 勾选专精即补足专精前置的技能等级 7 级（与 WPF 同口径）。
    private func masteryEnabledBinding(index: Int) -> Binding<Bool> {
        Binding {
            draft.masteries[index].isEnabled
        } set: { isOn in
            draft.masteries[index].isEnabled = isOn
            if isOn, draft.skillLevel != 0 {
                draft.skillLevel = 7
            }
        }
    }

    private func masteryRankBinding(index: Int) -> Binding<Int> {
        Binding {
            draft.masteries[index].rank
        } set: { newValue in
            draft.masteries[index].rank = newValue
        }
    }

    // MARK: - 待养成列表（一个条目 = 一名干员）

    private var planListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待养成")
                .font(.subheadline)

            if config.plans.isEmpty {
                Text("尚未添加干员，搜索选择后设置目标")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(config.plans.sorted { $0.name < $1.name }, id: \.self) { item in
                        characterRow(item)
                    }
                }
            }
        }
    }

    private func characterRow(_ item: OperProgressPlanItem) -> some View {
        let character = AutoRaiseDemandTable.shared[item.name]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    selectCharacter(item.name)
                } label: {
                    Text(item.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    removeItem(item)
                } label: {
                    Text("删除")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }
            ForEach(item.summaryTexts(character: character), id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
        }
    }

    // MARK: - 计划读写

    /// 以面板草稿替换该干员的计划条目（一名干员一个条目）。
    private func commitDraft() {
        guard let name = panelName else { return }
        config.plans.removeAll { $0.name == name }
        config.plans.append(draft.item(name: name))
    }

    private func removeItem(_ item: OperProgressPlanItem) {
        config.plans.removeAll { $0.name == item.name }
        if panelName == item.name {
            panelName = nil
        }
    }

    // MARK: - 计划 JSON（debug 视图，最终用户界面不保留）

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("养成计划 JSON（debug）")
                .font(.subheadline)

            Text("协议 plans 数组，未设定的字段不下发。")
                .font(.callout)
                .foregroundStyle(.secondary)

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
        }
    }

    private var debugJsonText: String {
        guard !config.plans.isEmpty else { return "[]" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config.plans),
            let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }

    // MARK: - 缺口报告

    @ViewBuilder private var gapReportSection: some View {
        if let inventory = viewModel.depot?.items {
            if let demand {
                let gap = demand.gap(against: inventory)
                VStack(alignment: .leading, spacing: 8) {
                    Text("缺口报告")
                        .font(.headline)

                    Text("计划不含当前等级，需求按各线最低档起算（实际所需不超过此值）。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

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

// MARK: - 面板草稿

/// 目标设置面板的草稿状态（一次编辑 = 一名干员的完整目标）。
private struct OperProgressGoalDraft: Hashable {
    /// 一行专精目标：勾选 + 目标档位（1-3）。
    struct Line: Hashable {
        var isEnabled = false
        var rank = 3
    }

    /// 职业；nil = 不设定（不下发 role 键）。
    var role: OperProgressRole?
    /// 精英化目标（nil = 不练，1/2 = 精一/精二）。
    var elite: Int?
    /// 技能等级目标（0 = 不设定；协议区间 2-7）。
    var skillLevel = 0
    /// 三行专精目标：下标 = 技能序号 − 1。
    var masteries = [Line(), Line(), Line()]

    init() {}

    /// 从该干员已有计划条目回填（按钮呈「更新」态）。
    init(item: OperProgressPlanItem) {
        role = item.role.flatMap(OperProgressRole.init(rawValue:))
        elite = item.elite
        switch item.skillLevel {
        case .base(let level):
            skillLevel = level
        case .specialization(let ranks):
            // 专精目标的隐式前置：技能基础等级 7 级（与 WPF 同口径）。
            skillLevel = 7
            for (index, rank) in ranks.enumerated() where masteries.indices.contains(index) && rank > 0 {
                masteries[index] = Line(isEnabled: true, rank: rank)
            }
        case nil:
            break
        }
    }

    /// 草稿 → 协议条目。
    func item(name: String) -> OperProgressPlanItem {
        OperProgressPlanItem(role: role?.rawValue, name: name, elite: elite, skillLevel: skillLevelValue)
    }

    /// 专精目标优先：协议 skill_level 是单键，有专精即下发三元素数组（未勾选的技能填 0）。
    private var skillLevelValue: SkillLevel? {
        let ranks = masteries.map { $0.isEnabled ? $0.rank : 0 }
        if ranks.contains(where: { $0 > 0 }) {
            return .specialization(ranks)
        }
        if skillLevel > 0 {
            return .base(skillLevel)
        }
        return nil
    }

    /// 技能序号（0 起）的序号标签；无需求表条目时的回退（有表则用技能真名）。
    static func ordinalLabel(_ index: Int) -> String {
        [String(localized: "一技能"), String(localized: "二技能"), String(localized: "三技能")][
            min(max(index, 0), 2)]
    }
}

// MARK: - 计划条目展示

private extension OperProgressPlanItem {
    /// 干员目标短语（一行一个目标），顺序同 WPF 的目标描述：专精 → 技能等级 → 精英化。
    func summaryTexts(character: AutoRaiseCharacterDemand?) -> [String] {
        var texts = [String]()
        if case .specialization(let ranks) = skillLevel {
            for (index, rank) in ranks.enumerated() where rank > 0 {
                let label = character?.skillLabel(index + 1) ?? OperProgressGoalDraft.ordinalLabel(index)
                texts.append(String(localized: "\(label)专精 → \(rank)"))
            }
        }
        if case .base(let level) = skillLevel {
            texts.append(String(localized: "技能 → \(level)"))
        }
        if let elite {
            texts.append(String(localized: "精英化 → \(elite)"))
        }
        return texts
    }

    /// 需求表口径的养成区间：协议不含当前等级，起点取各线最低档
    /// （精英化 0 / 技能 1 级 / 专精 0），即全量需求。
    var demandEntries: [AutoRaisePlan.Entry] {
        var entries = [AutoRaisePlan.Entry]()
        if let elite, (1...2).contains(elite) {
            entries.append(.init(name: name, action: .elite, from: 0, to: elite, skill: nil, level: nil))
        }
        switch skillLevel {
        case .base(let to):
            entries.append(.init(name: name, action: .skills, from: 1, to: to, skill: nil, level: nil))
        case .specialization(let ranks):
            for (index, to) in ranks.enumerated() where to > 0 {
                entries.append(.init(name: name, action: .mastery, from: 0, to: to, skill: index + 1, level: nil))
            }
        case nil:
            break
        }
        return entries
    }
}

/// 缺口报告的重算触发键：库存或计划变化即刷新材料名。
private struct OperProgressReportKey: Equatable {
    let items: [String: Int]?
    let plans: [OperProgressPlanItem]
}

struct OperProgressSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        OperProgressSettingsView(config: .constant(.init()))
            .environment(NewViewModel(parent: MAAViewModel()))
    }
}
