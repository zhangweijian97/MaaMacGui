//
//  OperProgressConfiguration.swift
//  MAA
//
//  干员培养（core 任务类型 OperProgress）的任务配置。
//

import Foundation

/// 干员培养：按计划列表逐名执行精英化/技能等级/技能专精培养。
///
/// 下发参数对齐 WPF `AsstOperProgressTask.Serialize()`：
/// `{"plans":[{"role":"Warrior","name":"陈","elite":2,"skill_level":7,"skill_mastery":[0,0,3]}]}`
/// 未设定的维度不带键；计划为空时启动阶段跳过该任务（对齐 WPF Serialize 语义）。
struct OperProgressConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .OperProgress }

    /// 培养计划：一个条目 = 一名干员的全部培养目标。
    var plans: [OperProgressPlan] = []

    var title: String {
        type.description
    }

    var subtitle: String {
        plans.isEmpty ? String(localized: "尚未添加干员") : String(localized: "计划 \(plans.count) 条")
    }

    var summary: String {
        plans.map(\.name).joined(separator: " ")
    }

    var projectedTask: MAATask {
        .operProgress(self)
    }

    typealias Params = OperProgressParams

    var params: OperProgressParams {
        .init(plans: plans)
    }
}

extension OperProgressConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.plans = try container.decodeIfPresent([OperProgressPlan].self, forKey: .plans) ?? []
    }
}
