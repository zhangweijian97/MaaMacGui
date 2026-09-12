//
//  AutoRaiseConfiguration.swift
//  MAA
//

import Foundation

/// 自动养成。
///
/// core 没有 AutoRaise 任务类型：运行本任务时实际下发给 core 的是 Depot（仓库识别）——
/// 只读取仓库库存、不改动游戏状态；配置页据库存报告计划的材料缺口。
/// 合成执行与轮次循环不在骨架范围内。
struct AutoRaiseConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .AutoRaise }

    /// 养成计划 JSON：条目列表，每条 = 一个养成目标（行动单元）。
    /// `[{"name": "银灰", "action": "Elite", "to": 2, "level": 90},
    ///    {"name": "银灰", "action": "Elite", "to": 0, "level": 45},
    ///    {"name": "银灰", "action": "Skills", "from": 4, "to": 7},
    ///    {"name": "银灰", "action": "Mastery", "skill": 3, "from": 0, "to": 3}]`
    /// 同干员同一条养成线（name + action + skill）只保留一条。
    var planJson: String = "[]"

    /// 合成完成后删除已完成条目（与 WPF 同名功能对齐的字段；骨架阶段不下发 core，不参与执行）。
    var deleteCompletedEntries: Bool = false

    var title: String {
        type.description
    }

    var subtitle: String {
        let plan = AutoRaisePlan(json: planJson)
        if plan.isUnparseable {
            return String(localized: "计划有误")
        }
        return String(localized: "计划 \(plan.entries.count) 条")
    }

    var summary: String {
        planJson.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
    }

    var projectedTask: MAATask {
        .autoRaise(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension AutoRaiseConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.planJson = container[.planJson, default: "[]"]
        self.deleteCompletedEntries = container[.deleteCompletedEntries, default: false]
    }
}

// MARK: - 养成计划

/// 养成动作，取值同 core AutoRaisePlan 的 action 字段。
enum AutoRaiseAction: String, CaseIterable, Sendable {
    case elite = "Elite"
    case skills = "Skills"
    case mastery = "Mastery"

    var title: String {
        switch self {
        case .elite:
            return String(localized: "精英化")
        case .skills:
            return String(localized: "技能等级")
        case .mastery:
            return String(localized: "专精")
        }
    }

    /// 该动作允许的 to（目标档位）区间；Elite 的 0 = 精英化 0 内升级（E0·1-60 级目标）。
    var targetRange: ClosedRange<Int> {
        switch self {
        case .elite:
            return 0...2
        case .skills:
            return 2...7
        case .mastery:
            return 1...3
        }
    }
}

/// 解析并校验后的养成计划：合法条目 + 逐条问题。
struct AutoRaisePlan: Hashable, Sendable {
    /// 单个养成目标（行动单元）。
    struct Entry: Hashable, Sendable {
        let name: String
        let action: AutoRaiseAction
        /// 起始档位：Elite 无 from（恒 0）；Skills 1-6；Mastery 0-2。
        let from: Int
        /// 目标档位：Elite 0-2（0 = 精英化 0）；Skills 2-7；Mastery 1-3。
        let to: Int
        /// 专精作用的技能序号（1 起），仅 Mastery 有。
        let skill: Int?
        /// 目标干员等级（1-90），仅 Elite 有；旧条目缺省 nil（升级耗经验书/龙门币，不进材料需求）。
        let level: Int?

        /// 养成线唯一键（同干员同线去重与删除定位用）。
        var lineKey: String {
            "\(name)|\(action.rawValue)|\(skill ?? 0)"
        }
    }

    struct Issue: Hashable, Sendable {
        /// 出错条目的下标（0 起）；nil 表示 JSON 整体不可解析。
        let index: Int?
        let message: String
    }

    var entries = [Entry]()
    var issues = [Issue]()

    /// JSON 整体不可解析（区别于逐条校验失败）。
    var isUnparseable = false

    init(json: String) {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // 空计划：0 条合法，不产生问题（编辑中途的常态）。
            return
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
        } catch {
            isUnparseable = true
            issues = [.init(index: nil, message: String(localized: "JSON 解析失败：\(error.localizedDescription)"))]
            return
        }

        guard let array = object as? [Any] else {
            isUnparseable = true
            issues = [.init(index: nil, message: String(localized: "JSON 解析失败：顶层应为数组"))]
            return
        }

        for (index, element) in array.enumerated() {
            append(element, index: index)
        }
    }

    private mutating func append(_ element: Any, index: Int) {
        func fail(_ reason: String) {
            issues.append(.init(index: index, message: String(localized: "第 \(index + 1) 条：\(reason)")))
        }

        guard let object = element as? [String: Any] else {
            fail(String(localized: "应为对象"))
            return
        }

        guard let name = object["name"] as? String, !name.isEmpty else {
            fail(String(localized: "name 缺失或为空"))
            return
        }

        guard let rawAction = object["action"] as? String, let action = AutoRaiseAction(rawValue: rawAction) else {
            fail(String(localized: "action 应为 Elite/Skills/Mastery"))
            return
        }

        guard let to = object["to"] as? Int, action.targetRange.contains(to) else {
            let range = action.targetRange
            fail(String(localized: "\(action.title)的 to 应为 \(range.lowerBound)-\(range.upperBound) 的整数"))
            return
        }

        // level：仅 Elite 携带的目标干员等级（1-90），缺省 nil（兼容旧条目）。
        var level: Int?
        if action == .elite, object["level"] != nil {
            guard let rawLevel = object["level"] as? Int, (1...90).contains(rawLevel) else {
                fail(String(localized: "level 应为 1-90 的整数"))
                return
            }
            level = rawLevel
        }

        // from：Elite 无（恒 0）；Skills/Mastery 缺省取全量起点，须小于 to。
        var from = 0
        if action != .elite {
            let lowerBound = action == .skills ? 1 : 0
            if let rawFrom = object["from"] as? Int {
                guard rawFrom >= lowerBound, rawFrom < to else {
                    fail(String(localized: "\(action.title)的 from 应为 \(lowerBound)-\(to - 1) 的整数"))
                    return
                }
                from = rawFrom
            } else {
                from = lowerBound
            }
        }

        var skill: Int?
        if action == .mastery {
            guard let rawSkill = object["skill"] as? Int, rawSkill >= 1 else {
                fail(String(localized: "Mastery 的 skill 应为 ≥ 1 的整数"))
                return
            }
            skill = rawSkill
        }

        let entry = Entry(name: name, action: action, from: from, to: to, skill: skill, level: level)
        // 同干员同线只保留一条：后写覆盖首次出现的位置。
        if let existing = entries.firstIndex(where: { $0.lineKey == entry.lineKey }) {
            entries[existing] = entry
        } else {
            entries.append(entry)
        }
    }

    /// 表单持久化与 debug 视图共用的规范化 pretty JSON（2 空格缩进，键排序）。
    var canonicalJson: String {
        let array = entries.map(\.jsonObject)
        guard !array.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }
}

extension AutoRaisePlan.Entry {
    var jsonObject: [String: Any] {
        var object: [String: Any] = ["name": name, "action": action.rawValue]
        if let skill {
            object["skill"] = skill
        }
        if action != .elite {
            object["from"] = from
        }
        object["to"] = to
        if action == .elite, let level {
            object["level"] = level
        }
        return object
    }
}

// MARK: - 需求与缺口

extension AutoRaisePlan {
    /// 计划累计需求：逐条按 from/to 区间查需求表增量，汇总为「材料 id → 数量」。
    /// 解析已保证同线唯一（后写覆盖），无需再聚合；排序只为让报告输出稳定。
    func demand(in table: [String: AutoRaiseCharacterDemand]) -> AutoRaiseDemand {
        var demand = AutoRaiseDemand()
        for entry in entries.sorted(by: {
            ($0.name, $0.action.rawValue, $0.skill ?? 0) < ($1.name, $1.action.rawValue, $1.skill ?? 0)
        }) {
            guard let character = table[entry.name] else {
                if !demand.unknownCharacters.contains(entry.name) {
                    demand.unknownCharacters.append(entry.name)
                }
                continue
            }
            guard let costs = character.costs(action: entry.action, skill: entry.skill, from: entry.from, to: entry.to) else {
                demand.noData.append(String(localized: "\(entry.name)：\(entry.action.title)无数据"))
                continue
            }
            for cost in costs {
                demand.items[cost.itemId, default: 0] += cost.count
            }
        }
        return demand
    }
}

/// 计划累计需求与查表问题。
struct AutoRaiseDemand: Sendable {
    /// 材料 id → 累计数量。
    var items = [String: Int]()
    /// 需求表里查不到的干员名。
    var unknownCharacters = [String]()
    /// 该养成线无数据（需求表对应维度为 null），报告为「无数据」不当 0。
    var noData = [String]()

    /// 缺口 = 需求 − 库存：差值 > 0 的条目按数量降序，其余计为已满足（同样携带明细）。
    func gap(against inventory: [String: Int]) -> AutoRaiseGap {
        var shortages = [AutoRaiseGap.Item]()
        var satisfied = [AutoRaiseGap.Item]()
        for (itemId, required) in items {
            let have = inventory[itemId] ?? 0
            let item = AutoRaiseGap.Item(itemId: itemId, required: required, have: have)
            if required > have {
                shortages.append(item)
            } else {
                satisfied.append(item)
            }
        }
        // 缺口降序；同量缺口按材料 id 升序，保证报告稳定。
        shortages.sort { lhs, rhs in
            lhs.shortfall == rhs.shortfall ? lhs.itemId < rhs.itemId : lhs.shortfall > rhs.shortfall
        }
        // 已满足按材料 id 升序（名称异步到达，用 id 才稳定）。
        satisfied.sort { $0.itemId < $1.itemId }
        return AutoRaiseGap(shortages: shortages, satisfied: satisfied)
    }
}

/// 缺口报告。
struct AutoRaiseGap: Sendable {
    struct Item: Hashable, Sendable, Identifiable {
        let itemId: String
        let required: Int
        let have: Int

        var id: String { itemId }
        var shortfall: Int { required - have }
    }

    var shortages = [Item]()
    var satisfied = [Item]()

    /// 需求材料总种数 = 缺口 + 已满足。
    var total: Int { shortages.count + satisfied.count }
}

// MARK: - 需求表

/// 单个干员的逐级养成需求（`mac_需求表.json` 的一条），材料为逐级增量。
struct AutoRaiseCharacterDemand: Codable, Sendable {
    let id: String
    /// 按技能序号（一/二/三技能）排列的技能名，显示层专用；无技能干员为空数组。
    let skillNames: [String]?
    /// 下标 i = 升到第 i+1 阶精英化的增量。
    let elite: [[MaterialCost]]?
    /// 下标 j = 技能从 j+1 升到 j+2 级的增量。
    let skills: [[MaterialCost]]?
    /// 外层下标 k = 第 k+1 技能，内层 m = 专精到 m+1 级的增量；null = 该技能无专精。
    let mastery: [[[MaterialCost]]?]?
}

extension AutoRaiseCharacterDemand {
    /// 技能序号（1 起）的显示名：表里有真名则「三技能（真银斩）」，否则回退序号标签。
    func skillLabel(_ number: Int) -> String {
        let ordinal = [String(localized: "一技能"), String(localized: "二技能"), String(localized: "三技能")][
            min(max(number - 1, 0), 2)]
        guard let names = skillNames, names.indices.contains(number - 1), !names[number - 1].isEmpty else {
            return ordinal
        }
        return String(localized: "\(ordinal)（\(names[number - 1])）")
    }
    /// from/to 区间需求：Elite 取前 to 阶；Skills 取第 from+1 到 to 级（from=1 即全量）；
    /// Mastery 取第 K 技能第 from+1 到 to 级。维度为 null 返回 nil（无数据，区别于空数组）。
    func costs(action: AutoRaiseAction, skill: Int?, from: Int, to: Int) -> [MaterialCost]? {
        switch action {
        case .elite:
            guard let elite else { return nil }
            return Self.slice(elite, lower: 0, upper: to)
        case .skills:
            guard let skills else { return nil }
            return Self.slice(skills, lower: from - 1, upper: to - 1)
        case .mastery:
            guard let skill, let mastery, mastery.indices.contains(skill - 1), let levels = mastery[skill - 1] else {
                return nil
            }
            return Self.slice(levels, lower: from, upper: to)
        }
    }

    /// 逐级增量数组的区间合计：取下标 [lower, upper) 段，等价 prefix(upper) − prefix(lower)。
    private static func slice(_ levels: [[MaterialCost]], lower: Int, upper: Int) -> [MaterialCost] {
        let start = max(0, lower)
        let end = min(upper, levels.count)
        guard start < end else { return [] }
        return levels[start..<end].flatMap { $0 }
    }
}

/// 材料消耗条目，结构同需求表的 `[itemId, 数量]`。
struct MaterialCost: Codable, Hashable, Sendable {
    let itemId: String
    let count: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.itemId = try container.decode(String.self)
        self.count = try container.decode(Int.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(itemId)
        try container.encode(count)
    }
}

enum AutoRaiseDemandTable {
    /// 随 app 打包的全量干员需求表（按中文名索引）；读取失败则为空表，报告逐条标「需求表无此干员」。
    static let shared: [String: AutoRaiseCharacterDemand] = {
        guard let url = Bundle.main.url(forResource: "mac_需求表", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let table = try? JSONDecoder().decode([String: AutoRaiseCharacterDemand].self, from: data)
        else {
            return [:]
        }
        return table
    }()
}
