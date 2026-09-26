//
//  DepotMaintainConfiguration.swift
//  MAA
//
//  Created by zhangweijian on 26/9/2026.
//

import Foundation

/// 「库存保持」任务配置（对齐 WPF `DepotMaintainTask`）。
///
/// 自身不占 core 任务类型，只编排已注册的仓库识别与理智作战：先识别一次库存，
/// 再按保持计划把库存不足的材料刷到目标数量。
struct DepotMaintainConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .DepotMaintain }

    /// 任务开始前先识别一次仓库，用最新库存计算各计划缺口
    var updateDepot: Bool

    /// 启用各计划的「吃理智药」预算（关闭时计划内不显示，下发时按 0 处理）
    var useMedicine: Bool

    /// 启用各计划的「吃源石」预算
    var useStone: Bool

    /// 使用 48 小时内过期的理智药（对齐 WPF 的固定 2 天阈值）
    var useExpiringMedicine: Bool

    /// 使用 AUTO 代理倍率（core 的 series = 0）；关闭时按 1 倍刷取
    var useAutoSeries: Bool

    /// 仅下发第一个库存不足的计划，其补满后由下次运行继续后续计划
    var onlyFirstInsufficientPlan: Bool

    /// 保持计划：把计划中的材料补到目标库存
    var plans: [Plan]

    /// 本轮规划产物（不持久化）：已按当前库存算好缺口的作战任务
    var fights: [FightTask] = []

    var title: String {
        type.description
    }

    var subtitle: String {
        plans.isEmpty
            ? String(localized: "未配置任何计划")
            : String(localized: "保持计划") + " ×\(plans.count)"
    }

    var summary: String {
        var parts = [String]()
        if updateDepot {
            parts.append(String(localized: "任务开始前更新库存数据"))
        }
        if onlyFirstInsufficientPlan {
            parts.append(String(localized: "仅执行第一个库存不足的计划"))
        }
        return parts.joined(separator: ";")
    }

    var projectedTask: MAATask {
        .depotmaintain(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }

    private enum CodingKeys: String, CodingKey {
        case updateDepot
        case useMedicine
        case useStone
        case useExpiringMedicine
        case useAutoSeries
        case onlyFirstInsufficientPlan
        case plans
    }
}

extension DepotMaintainConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.updateDepot = try container.decodeIfPresent(Bool.self, forKey: .updateDepot) ?? true
        self.useMedicine = try container.decodeIfPresent(Bool.self, forKey: .useMedicine) ?? true
        self.useStone = try container.decodeIfPresent(Bool.self, forKey: .useStone) ?? true
        self.useExpiringMedicine = try container.decodeIfPresent(Bool.self, forKey: .useExpiringMedicine) ?? false
        self.useAutoSeries = try container.decodeIfPresent(Bool.self, forKey: .useAutoSeries) ?? false
        self.onlyFirstInsufficientPlan =
            try container.decodeIfPresent(Bool.self, forKey: .onlyFirstInsufficientPlan) ?? false
        self.plans = try container.decodeIfPresent([Plan].self, forKey: .plans) ?? []
        self.fights = []
    }
}

extension DepotMaintainConfiguration {
    /// 一条保持计划：把 `dropId` 材料补到 `dropCount`（目标库存）。
    struct Plan: Codable, Hashable, Sendable {
        /// 关卡名（core 关卡代码，如 CE-6）
        var stage: String = ""
        /// 材料 ID（对应资源中的 item_index.json）
        var dropId: String = ""
        /// 目标库存
        var dropCount: Int = 0
        /// 本关是否使用理智药
        var useMedicine: Bool = false
        /// 理智药使用上限
        var medicineCount: Int = 0
        /// 本关是否使用源石
        var useStone: Bool = false
        /// 源石使用上限
        var stoneCount: Int = 0
    }

    /// 一轮实际下发的作战任务（规划产物，不持久化）。
    struct FightTask: Hashable, Sendable {
        /// 计划序号（1 起，日志标注用）
        let index: Int
        /// 该计划的材料与目标库存，任务开始前按最新库存重算缺口时要用
        let plan: Plan
        /// 下发参数，其中 `drops` 为规划时算得的缺口
        var config: FightConfiguration
    }
}

extension DepotMaintainConfiguration.Plan {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stage = try container.decodeIfPresent(String.self, forKey: .stage) ?? ""
        self.dropId = try container.decodeIfPresent(String.self, forKey: .dropId) ?? ""
        self.dropCount = try container.decodeIfPresent(Int.self, forKey: .dropCount) ?? 0
        self.useMedicine = try container.decodeIfPresent(Bool.self, forKey: .useMedicine) ?? false
        self.medicineCount = try container.decodeIfPresent(Int.self, forKey: .medicineCount) ?? 0
        self.useStone = try container.decodeIfPresent(Bool.self, forKey: .useStone) ?? false
        self.stoneCount = try container.decodeIfPresent(Int.self, forKey: .stoneCount) ?? 0
    }
}

extension DepotMaintainConfiguration {
    /// 临期理智药阈值（天），对齐 WPF `DepotMaintainTask.ExpiringMedicineDays`
    static let expiringMedicineDays = 2

    /// 由一条计划构建作战任务参数。
    ///
    /// 对齐 WPF：`MaxTimes` 不限次（缺口由 `drops` 决定何时停），药剂/源石受本任务的总开关与计划自身开关双重约束，
    /// 代理倍率按总开关取 AUTO（series = 0）或 1 倍。
    /// - Parameter need: 本轮需刷取数量（目标库存 − 当前库存）
    func fightConfiguration(for plan: Plan, need: Int) -> FightConfiguration {
        FightConfiguration(
            stage: plan.stage,
            medicine: useMedicine && plan.useMedicine ? plan.medicineCount : 0,
            medicine_expire_days: useExpiringMedicine ? Self.expiringMedicineDays : 0,
            stone: useStone && plan.useStone ? plan.stoneCount : 0,
            times: nil,
            series: useAutoSeries ? 0 : 1,
            drops: [plan.dropId: need],
            report_to_penguin: false,
            penguin_id: "",
            server: "CN",
            client_type: "",
            DrGrandet: false)
    }
}
