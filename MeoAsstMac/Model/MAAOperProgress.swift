//
//  MAAOperProgress.swift
//  MAA
//
//  干员培养（OperProgress）任务的协议模型与干员数据目录。
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.hguandl.MeoAsstMac", category: "OperProgress")

// MARK: - 职业

/// 干员职业，rawValue 即 core `battle::Role` 的拼写（协议 `role` 键取值）。
enum OperProgressRole: String, Codable, CaseIterable, Identifiable, Sendable {
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

    /// `battle_data.json` 的 profession 字段（全大写）到职业的映射；不在八职业白名单内返回 nil。
    init?(profession: String) {
        switch profession {
        case "PIONEER":
            self = .pioneer
        case "WARRIOR":
            self = .warrior
        case "TANK":
            self = .tank
        case "SNIPER":
            self = .sniper
        case "CASTER":
            self = .caster
        case "MEDIC":
            self = .medic
        case "SUPPORT":
            self = .support
        case "SPECIAL":
            self = .special
        default:
            return nil
        }
    }
}

// MARK: - 培养计划

/// 单名干员的培养目标（配置持久化模型）。
///
/// 字段语义与协议一致：`elite` / `skillLevel` 为 0、`skillMastery` 全 0 表示不设定该维度，
/// 下发参数时不带对应键。下发形态见 `OperProgressParams`（core 白名单只有 5 键，
/// 本模型的 `id` 等内部字段不会发给 core）。
struct OperProgressPlan: Codable, Hashable, Identifiable, Sendable {
    /// 列表身份与展开状态用（不参与协议下发）。
    var id = UUID()
    /// 干员职业；nil = 不带 `role` 键，由 core 按名字识别（同名多职业时必需）。
    var role: OperProgressRole?
    /// 干员中文名（协议必填）。
    var name: String
    /// 精英化目标：0 = 不设定，1 = 精一，2 = 精二。
    var elite = 0
    /// 技能基础等级目标：0 = 不设定，2–7 级。
    var skillLevel = 0
    /// 技能 1/2/3 的专精目标（恒 3 个元素），0 = 该技能不专精。
    var skillMastery = [0, 0, 0]

    enum CodingKeys: String, CodingKey {
        case id, role, name, elite
        case skillLevel = "skill_level"
        case skillMastery = "skill_mastery"
    }
}

extension OperProgressPlan {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.role = try container.decodeIfPresent(OperProgressRole.self, forKey: .role)
        self.name = try container.decode(String.self, forKey: .name)
        self.elite = try container.decodeIfPresent(Int.self, forKey: .elite) ?? 0
        self.skillLevel = try container.decodeIfPresent(Int.self, forKey: .skillLevel) ?? 0
        let mastery = try container.decodeIfPresent([Int].self, forKey: .skillMastery) ?? []
        self.skillMastery = (0..<3).map { mastery.indices.contains($0) ? mastery[$0] : 0 }
    }
}

/// appendTask 的 `plans` 参数：对齐 WPF `AsstOperProgressTask.Serialize()`。
struct OperProgressParams: Encodable {
    let plans: [OperProgressPlan]

    enum CodingKeys: String, CodingKey {
        case plans
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var list = container.nestedUnkeyedContainer(forKey: .plans)
        for plan in plans {
            try list.encode(ProtocolPlan(plan: plan))
        }
    }

    /// 协议形态的条目：只写 core 白名单 5 键，0/空值不带键。
    private struct ProtocolPlan: Encodable {
        let plan: OperProgressPlan

        enum CodingKeys: String, CodingKey {
            case role, name, elite
            case skillLevel = "skill_level"
            case skillMastery = "skill_mastery"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let role = plan.role {
                try container.encode(role, forKey: .role)
            }
            try container.encode(plan.name, forKey: .name)
            if plan.elite > 0 {
                try container.encode(plan.elite, forKey: .elite)
            }
            if plan.skillLevel > 0 {
                try container.encode(plan.skillLevel, forKey: .skillLevel)
            }
            if plan.skillMastery.contains(where: { $0 > 0 }) {
                try container.encode(plan.skillMastery, forKey: .skillMastery)
            }
        }
    }
}

// MARK: - 剪贴板解析

/// 工具箱计划 JSON 的解析失败原因；任何一项失败即整体失败（不部分导入）。
enum OperProgressParseError: LocalizedError {
    case invalidJSON(String)
    case notArray
    case invalidItem(index: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let reason):
            return "剪贴板不是合法 JSON：\(reason)"
        case .notArray:
            return "剪贴板 JSON 应为计划数组"
        case .invalidItem(let index, let reason):
            return "第 \(index) 项无效：\(reason)"
        }
    }
}

enum OperProgressPlanParser {
    /// 解析工具箱导出的计划 JSON 数组（`[{"role":"Warrior","name":"陈","elite":2,...}]`）。
    /// 未知键忽略正常导入（对齐 WPF cs:376-395——工具箱导出带额外字段时不整单拒绝）；
    /// `role` 缺失或非法时按干员数据反查补全；名字缺失或查无即整体报错。
    static func parse(_ text: String) throws -> [OperProgressPlan] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OperProgressParseError.invalidJSON("内容为空")
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw OperProgressParseError.invalidJSON("编码无效")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw OperProgressParseError.invalidJSON(error.localizedDescription)
        }
        guard let items = object as? [Any] else {
            throw OperProgressParseError.notArray
        }

        let directory = OperProgressOperatorDirectory.shared
        var plans = [OperProgressPlan]()
        plans.reserveCapacity(items.count)

        for (offset, item) in items.enumerated() {
            let index = offset + 1
            guard let dict = item as? [String: Any] else {
                throw OperProgressParseError.invalidItem(index: index, reason: "应为对象")
            }

            guard let rawName = dict["name"] as? String,
                !rawName.trimmingCharacters(in: .whitespaces).isEmpty
            else {
                throw OperProgressParseError.invalidItem(index: index, reason: "缺少干员名")
            }
            let name = rawName.trimmingCharacters(in: .whitespaces)

            var role: OperProgressRole?
            if let rawRole = dict["role"] as? String {
                role = OperProgressRole(rawValue: rawRole)
            }
            if role == nil {
                role = directory.role(matchingName: name)
            }
            guard let role else {
                throw OperProgressParseError.invalidItem(index: index, reason: "干员数据中找不到「\(name)」")
            }

            var mastery = [0, 0, 0]
            if let rawMastery = dict["skill_mastery"] {
                guard let rawMastery = rawMastery as? [Any] else {
                    throw OperProgressParseError.invalidItem(index: index, reason: "skill_mastery 应为整数数组")
                }
                let values = rawMastery.compactMap { ($0 as? NSNumber)?.intValue }
                guard values.count == rawMastery.count else {
                    throw OperProgressParseError.invalidItem(index: index, reason: "skill_mastery 应为整数数组")
                }
                for i in 0..<min(3, values.count) {
                    mastery[i] = values[i]
                }
            }

            plans.append(
                OperProgressPlan(
                    role: role,
                    name: name,
                    elite: try intValue(dict["elite"], index: index, key: "elite") ?? 0,
                    skillLevel: try intValue(dict["skill_level"], index: index, key: "skill_level") ?? 0,
                    skillMastery: mastery))
        }
        return plans
    }

    private static func intValue(_ value: Any?, index: Int, key: String) throws -> Int? {
        guard let value else { return nil }
        guard let number = value as? NSNumber else {
            throw OperProgressParseError.invalidItem(index: index, reason: "\(key) 应为整数")
        }
        return number.intValue
    }
}

// MARK: - 干员数据目录

/// `battle_data.json` 干员条目的精简投影（只留名称/职业/星级）。
struct OperProgressOperator: Hashable, Identifiable, Sendable {
    let id: String
    /// 中文名（协议 `name` 键与数据反查用）。
    let name: String
    /// 按 App 语言显示的本地化名。
    let displayName: String
    let role: OperProgressRole
    /// 星级（battle_data 原值即 1–6 星，实测「陈」= 6）。
    let rarity: Int
    /// 同名（多职业/多形态）时显示加职业后缀消歧。
    let hasSameName: Bool

    /// 选择列表显示名。
    var selectionTitle: String {
        hasSameName ? "\(displayName)-\(role.title)" : displayName
    }

    /// 培养技能数：6 星 3 个，4/5 星 2 个，3 星 1 个，其余无技能；
    /// 阿米娅本体 5 星但 3 技能（对齐 WPF `oper.Id == "char_002_amiya"` 特判）。
    var skillCount: Int {
        if id == "char_002_amiya" {
            return 3
        }
        switch rarity {
        case 6:
            return 3
        case 5, 4:
            return 2
        case 3:
            return 1
        default:
            return 0
        }
    }
}

/// 干员数据目录：首次访问时解析 `resource/battle_data.json` 一次并缓存。
enum OperProgressOperatorDirectory {
    /// 培养流程未验证的三个阿米娅形态，从选择列表屏蔽（对齐 WPF）。
    static let blockedIDs: Set<String> = ["char_002_amiya", "char_1001_amiya2", "char_1037_amiya3"]

    static let shared = Directory.load()

    struct Directory: Sendable {
        /// 可选择的干员（已过滤、按下拉顺序排序：稀有度降序 → 显示名升序）。
        let all: [OperProgressOperator]

        private let byName: [String: [OperProgressOperator]]

        static let empty = Directory(all: [], byName: [:])

        /// 中文名反查职业（role 缺失/非法时的补全）。
        func role(matchingName name: String) -> OperProgressRole? {
            byName[name]?.first?.role
        }

        /// 按名字（可带职业）查干员。
        func findOperator(named name: String, role: OperProgressRole?) -> OperProgressOperator? {
            guard let candidates = byName[name] else { return nil }
            if let role {
                return candidates.first { $0.role == role }
            }
            return candidates.first
        }

        /// 卡片头像路径；加载失败（nil）时由界面降级为占位图。
        func avatarURL(for id: String) -> URL? {
            Self.resourceURL(relativePath: "resource/template/avatar/\(id).png")
        }

        /// 用户更新过的资源优先（与 core 的资源加载顺序一致：用户目录后加载、覆盖内置）。
        static func resourceURL(relativePath: String) -> URL? {
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let external = documents.appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: external.path) {
                    return external
                }
            }
            return Bundle.main.resourceURL?.appendingPathComponent(relativePath)
        }

        static func load() -> Directory {
            guard let url = battleDataURL else {
                logger.error("battle_data.json not found")
                return .empty
            }

            let chars: [String: OperatorEntry]
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                chars = try decoder.decode(BattleData.self, from: Data(contentsOf: url)).chars
            } catch {
                logger.error("Failed to load battle_data.json: \(error)")
                return .empty
            }

            let language = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
            var candidates = [OperProgressOperator]()
            for (id, entry) in chars {
                // 屏蔽的阿米娅形态不进选择列表，但保留进反查目录：
                // 剪贴板导入近卫/医疗形态（role+名匹配）时按 5 星=2 技能解析
                // （对齐 WPF——屏蔽只在 OperatorNames 列表，条目 VM 仍可按名解析）。
                guard let name = entry.name, !name.isEmpty else { continue }
                guard let profession = entry.profession, let role = OperProgressRole(profession: profession) else {
                    continue
                }
                candidates.append(
                    OperProgressOperator(
                        id: id,
                        name: name,
                        displayName: Self.localizedName(entry, language: language),
                        role: role,
                        rarity: entry.rarity ?? 0,
                        hasSameName: false))
            }

            var sameNameCounts = [String: Int]()
            for entry in candidates {
                sameNameCounts[entry.name, default: 0] += 1
            }
            let entries = candidates.map { entry in
                OperProgressOperator(
                    id: entry.id,
                    name: entry.name,
                    displayName: entry.displayName,
                    role: entry.role,
                    rarity: entry.rarity,
                    hasSameName: sameNameCounts[entry.name, default: 0] > 1)
            }

            // 可选择列表：屏蔽形态剔除、按下拉顺序排序（稀有度降序 → 显示名升序）
            let selectable = entries.filter { !blockedIDs.contains($0.id) }.sorted { lhs, rhs in
                if lhs.rarity != rhs.rarity {
                    return lhs.rarity > rhs.rarity
                }
                let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.id < rhs.id
            }

            let byName = Dictionary(grouping: entries, by: \.name)
            return Directory(all: selectable, byName: byName)
        }

        private static func localizedName(_ entry: OperatorEntry, language: String) -> String {
            switch language {
            case "en":
                return entry.nameEn ?? entry.name ?? ""
            case "ko":
                return entry.nameKr ?? entry.name ?? ""
            case "zh-Hant":
                return entry.nameTw ?? entry.name ?? ""
            default:
                return entry.name ?? ""
            }
        }

        private static var battleDataURL: URL? {
            resourceURL(relativePath: "resource/battle_data.json")
        }

        // MARK: battle_data.json 解码结构

        private struct OperatorEntry: Decodable {
            let name: String?
            let nameEn: String?
            let nameJp: String?
            let nameKr: String?
            let nameTw: String?
            let profession: String?
            let rarity: Int?
        }

        private struct BattleData: Decodable {
            let chars: [String: OperatorEntry]
        }
    }
}
