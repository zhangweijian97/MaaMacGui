//
//  AutoRaiseConfiguration.swift
//  MAA
//

import Foundation

/// 自动养成（只读骨架）。
///
/// core 没有 AutoRaise 任务类型：运行本任务时实际下发给 core 的是 Depot（仓库识别）——
/// 只读取仓库库存、不改动游戏状态；配置页据库存报告计划的材料缺口。
/// 合成执行与轮次循环不在骨架范围内。
struct AutoRaiseConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .AutoRaise }

    /// 养成计划 JSON，条目语义同 core 的 AutoRaisePlan：
    /// `[{"name": "银灰", "action": "Elite", "target": 2, "skill": 3}]`
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

    /// 该动作允许的 target 区间。
    var targetRange: ClosedRange<Int> {
        switch self {
        case .elite:
            return 1...2
        case .skills:
            return 2...7
        case .mastery:
            return 1...3
        }
    }
}

/// 解析并校验后的养成计划：合法条目 + 逐条问题。
struct AutoRaisePlan: Hashable, Sendable {
    struct Entry: Hashable, Sendable {
        let name: String
        let action: AutoRaiseAction
        let target: Int
        let skill: Int?
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

        guard let target = object["target"] as? Int, action.targetRange.contains(target) else {
            let range = action.targetRange
            fail(String(localized: "\(action.title)的 target 应为 \(range.lowerBound)-\(range.upperBound) 的整数"))
            return
        }

        var skill: Int?
        if action == .mastery {
            guard let rawSkill = object["skill"] as? Int, rawSkill >= 1 else {
                fail(String(localized: "Mastery 的 skill 应为 ≥ 1 的整数"))
                return
            }
            skill = rawSkill
        }

        entries.append(.init(name: name, action: action, target: target, skill: skill))
    }
}

// MARK: - 需求与缺口

extension AutoRaisePlan {
    /// 养成线：同名同线取最大 target（不叠加），不同线叠加；专精线由技能区分。
    private struct Line: Hashable {
        let name: String
        let action: AutoRaiseAction
        let skill: Int?
    }

    /// 计划累计需求：按需求表逐级累加，汇总为「材料 id → 数量」。
    func demand(in table: [String: AutoRaiseCharacterDemand]) -> AutoRaiseDemand {
        var demands = [Line: Int]()
        for entry in entries {
            let line = Line(name: entry.name, action: entry.action, skill: entry.action == .mastery ? entry.skill : nil)
            demands[line] = max(demands[line] ?? 0, entry.target)
        }

        var demand = AutoRaiseDemand()
        // 排序只为让报告输出稳定（累加与顺序无关）。
        for (line, target) in demands.sorted(by: { ($0.key.name, $0.key.action.rawValue) < ($1.key.name, $1.key.action.rawValue) }) {
            guard let character = table[line.name] else {
                if !demand.unknownCharacters.contains(line.name) {
                    demand.unknownCharacters.append(line.name)
                }
                continue
            }
            guard let costs = character.costs(action: line.action, target: target, skill: line.skill) else {
                demand.noData.append(String(localized: "\(line.name)：\(line.action.title)无数据"))
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
    /// 下标 i = 升到第 i+1 阶精英化的增量。
    let elite: [[MaterialCost]]?
    /// 下标 j = 技能从 j+1 升到 j+2 级的增量。
    let skills: [[MaterialCost]]?
    /// 外层下标 k = 第 k+1 技能，内层 m = 专精到 m+1 级的增量；null = 该技能无专精。
    let mastery: [[[MaterialCost]]?]?
}

extension AutoRaiseCharacterDemand {
    /// 逐级累加：Elite 取前 N 阶、Skills 取前 N-1 级、Mastery 取第 K 技能前 N 级。
    /// 维度为 null 返回 nil（无数据，区别于空数组）。
    func costs(action: AutoRaiseAction, target: Int, skill: Int?) -> [MaterialCost]? {
        switch action {
        case .elite:
            guard let elite else { return nil }
            return elite.prefix(target).flatMap { $0 }
        case .skills:
            guard let skills else { return nil }
            return skills.prefix(target - 1).flatMap { $0 }
        case .mastery:
            guard let skill, let mastery, mastery.indices.contains(skill - 1), let levels = mastery[skill - 1] else {
                return nil
            }
            return levels.prefix(target).flatMap { $0 }
        }
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
