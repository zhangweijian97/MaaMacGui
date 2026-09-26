//
//  OperProgressConfiguration.swift
//  MAA
//

import Foundation

/// 干员培养（上游 core 任务类型 OperProgress）。
///
/// 下发参数（对齐 Windows WPF `AsstOperProgressTask.Serialize()`）：
/// `{"plans": [{"role": "Warrior", "name": "银灰", "elite": 2, "skill_level": [0, 3, 3]}]}`
/// - 键名全 snake_case；`role`/`elite`/`skill_level` 缺省 = 不带该键（不是 null）；
/// - 字段出现即动作：`elite` = 2 表示精英化到精二；`skill_level` = 7 表示技能升到 7 级；
///   `skill_level` = `[0, 3, 3]` 表示三个技能各自的专精目标（0 = 不专精）
struct OperProgressConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .OperProgress }

    /// 培养计划：一个条目 = 一名干员的全部培养目标。
    var plans: [OperProgressPlanItem] = []

    var title: String {
        type.description
    }

    var subtitle: String {
        if plans.isEmpty {
            return String(localized: "尚未添加干员，搜索选择后设置目标")
        }
        return String(localized: "计划 \(plans.count) 条")
    }

    var summary: String {
        plans.map(\.name).joined(separator: " ")
    }

    var projectedTask: MAATask {
        .operProgress(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension OperProgressConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 旧 v1 计划（`[{name, action, from, to, skill}]`，本仓自动养成骨架的格式）与
        // 协议结构不兼容，解码失败即重置为空计划：不崩、不留迁移逻辑。
        self.plans = (try? container.decode([OperProgressPlanItem].self, forKey: .plans)) ?? []
    }
}

// MARK: - 培养计划条目

/// 单名干员的培养目标，协议 `plans` 数组里的一项。
struct OperProgressPlanItem: Codable, Hashable, Sendable {
    /// 干员职业（协议 `role`，取值同 core Role 枚举名）；nil = 不带该键，由 core 按名字识别。
    /// 同名干员分属不同职业时用它消歧。
    var role: String?
    /// 干员名（协议必填）。
    var name: String
    /// 精英化目标（1 = 精一、2 = 精二）；nil = 不带该键。
    var elite: Int?
    /// 技能目标；nil = 不带该键。
    var skillLevel: SkillLevel?

    enum CodingKeys: String, CodingKey {
        case role
        case name
        case elite
        case skillLevel = "skill_level"
    }

    /// 协议允许的键（与 core `OperProgressTask` 的 allowed_keys 一致）。
    static let allowedKeys: Set<String> = ["role", "name", "elite", "skill_level"]
}

/// 任意键名的编码键：用于读出条目里的全部键（CodingKeys 只看得到自己声明过的键）。
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = String(intValue) }
}

extension OperProgressPlanItem {
    init(from decoder: any Decoder) throws {
        // 只接受协议四键：多出的键（如旧 v1 的 action/from/to/skill）视为旧数据/脏数据，
        // 解码失败后由 OperProgressConfiguration 重置为空计划。
        let rawKeys = try decoder.container(keyedBy: AnyCodingKey.self).allKeys
        guard rawKeys.allSatisfy({ Self.allowedKeys.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "plan item contains unknown keys: \(rawKeys.map(\.stringValue))"))
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try container.decodeIfPresent(String.self, forKey: .role)
        self.name = try container.decode(String.self, forKey: .name)
        self.elite = try container.decodeIfPresent(Int.self, forKey: .elite)
        self.skillLevel = try container.decodeIfPresent(SkillLevel.self, forKey: .skillLevel)
    }
}

/// 技能目标（协议 `skill_level` 的两种形态）。
enum SkillLevel: Hashable, Sendable {
    /// 技能等级升到该级（2-7）。
    case base(Int)
    /// 一/二/三技能各自的专精目标（0 = 不专精，1-3 = 专精档位），恒三个元素。
    case specialization([Int])
}

extension SkillLevel: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let level = try? container.decode(Int.self) {
            self = .base(level)
            return
        }
        let ranks = try container.decode([Int].self)
        guard ranks.count == 3 else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "skill_level 数组应为三个技能各自的专精目标")
        }
        self = .specialization(ranks)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .base(let level):
            try container.encode(level)
        case .specialization(let ranks):
            try container.encode(ranks)
        }
    }
}

// MARK: - 职业

/// 干员职业（协议 `role` 的取值 = core Role 枚举名）；不设定时不下发 `role` 键。
enum OperProgressRole: String, CaseIterable, Identifiable, Sendable {
    case pioneer = "Pioneer"
    case warrior = "Warrior"
    case tank = "Tank"
    case sniper = "Sniper"
    case caster = "Caster"
    case medic = "Medic"
    case support = "Support"
    case special = "Special"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pioneer:
            return String(localized: "先锋")
        case .warrior:
            return String(localized: "近卫")
        case .tank:
            return String(localized: "重装")
        case .sniper:
            return String(localized: "狙击")
        case .caster:
            return String(localized: "术师")
        case .medic:
            return String(localized: "医疗")
        case .support:
            return String(localized: "辅助")
        case .special:
            return String(localized: "特种")
        }
    }
}
