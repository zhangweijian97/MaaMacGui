//
//  OperProgressCallbackConsumer.swift
//  MAA
//
//  干员培养回调（Detail/Summary）消费的纯逻辑：从 MAAViewModel 扩展抽出
//  （goal-0729d7 可测性抽取），无 ViewModel/UI 依赖，行为零变化。
//

import Foundation

/// 干员培养回调（Detail/Summary）的纯数据快照：core 消息体关注字段的子集。
/// 键缺失（nil）= core 未报告该维度，不参与达成比对（对齐 WPF `int?`/`SkillMastery?` 语义）。
struct OperProgressCallbackSnapshot: Equatable {
    let role: String?
    let name: String
    let elite: Int?
    let skillLevel: Int?
    let skillMastery: [Int]?
}

/// Detail 回调的消费结果。
struct OperProgressDetailOutcome {
    /// 消费后的完整计划列表（无匹配时与输入相同）。
    let plans: [OperProgressPlan]
    /// 匹配到的条目下标；nil = 无匹配条目（调用方记日志后忽略该消息）。
    let matchedIndex: Int?
    /// 是否发生清零写回。
    let modified: Bool
}

/// 干员培养回调消费（对齐 WPF OperProgressTaskUserControlModel）。
enum OperProgressCallbackConsumer {
    /// Summary 后移除已完成条目。完成判据=该条目全维度清零
    /// （elite/skillLevel/专精全 0），不是 success 计数。
    static func removingFinishedPlans(from plans: [OperProgressPlan]) -> [OperProgressPlan] {
        plans.filter { plan in
            plan.elite != 0 || plan.skillLevel != 0 || plan.skillMastery.contains { $0 > 0 }
        }
    }

    /// Detail 回调：达成维度清零（WPF `ProcOperProgressMsg` 的匹配与写回部分——
    /// 不实时刷 UI，刷新统一在 Summary 之后由移除逻辑触发）。
    static func consumeDetail(
        _ snapshot: OperProgressCallbackSnapshot,
        in plans: [OperProgressPlan]
    ) -> OperProgressDetailOutcome {
        let callbackRole = snapshot.role.flatMap(OperProgressRole.init(rawValue:))

        // 匹配条目：先按职业+名字，退化为仅名字（对齐 WPF 两段 FirstOrDefault）
        guard let index = plans.firstIndex(where: { $0.role == callbackRole && $0.name == snapshot.name })
            ?? plans.firstIndex(where: { $0.name == snapshot.name })
        else {
            return OperProgressDetailOutcome(plans: plans, matchedIndex: nil, modified: false)
        }

        var plan = plans[index]
        var isModified = false
        if let elite = snapshot.elite, elite >= plan.elite {
            plan.elite = 0
            isModified = true
        }
        if let skillLevel = snapshot.skillLevel, skillLevel >= plan.skillLevel {
            plan.skillLevel = 0
            isModified = true
        }
        if let mastery = snapshot.skillMastery {
            var spec = plan.skillMastery
            var specChanged = false
            for skill in 0..<min(3, mastery.count) where mastery[skill] >= spec[skill] {
                spec[skill] = 0
                specChanged = true
            }
            if specChanged {
                plan.skillMastery = spec
                isModified = true
            }
        }
        if isModified {
            var result = plans
            result[index] = plan
            return OperProgressDetailOutcome(plans: result, matchedIndex: index, modified: true)
        }
        return OperProgressDetailOutcome(plans: plans, matchedIndex: index, modified: false)
    }
}
