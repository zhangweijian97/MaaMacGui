//
//  OperProgressPlanEditor.swift
//  MAA
//
//  干员培养计划条目的编辑态模型：互斥规则纯逻辑，从计划卡片 View 抽出
//  （goal-0729d7 可测性抽取），无 UI 依赖，行为零变化。
//

import Foundation

/// 单条培养计划的编辑态：勾选与目标值分开存放（对齐 WPF 条目 VM——取消勾选只把
/// 写回值归零，目标值在存续期间保留，重新勾选即恢复）。
///
/// 互斥规则（对齐 WPF OperProgressPlanItemViewModel）：
/// - 等级设 1–6 清空专精（5a；UI 下拉无 Lv.1，实际触发域 2–6）；
/// - 设专精且已有等级目标自动补至 7 级（5b；等级未设定时保持不设定）；
/// - 勾选专精且未选档位自动设专 3（5c）；
/// - 未勾选维度写回按 0 产出（5d）。
struct OperProgressPlanEditor {
    var eliteEnabled: Bool
    var eliteValue: Int
    var levelEnabled: Bool
    var levelValue: Int
    /// 恒 3 个元素（与 `OperProgressPlan.skillMastery` 对齐）。
    var masteryEnabled: [Bool]
    var masteryValues: [Int]

    /// 从计划加载编辑态：各勾选 = 对应值 > 0；未设定时目标值取该维度默认（精 2 / 7 级 / 专 3）。
    init(plan: OperProgressPlan) {
        let mastery = (0..<3).map { plan.skillMastery.indices.contains($0) ? plan.skillMastery[$0] : 0 }
        self.eliteEnabled = plan.elite > 0
        self.eliteValue = plan.elite > 0 ? plan.elite : 2
        self.levelEnabled = plan.skillLevel > 0
        self.levelValue = plan.skillLevel > 0 ? plan.skillLevel : 7
        self.masteryEnabled = mastery.map { $0 > 0 }
        self.masteryValues = mastery.map { $0 > 0 ? $0 : 3 }
    }
}

// MARK: - 编辑规则（对齐 WPF OperProgressPlanItemViewModel）

extension OperProgressPlanEditor {
    mutating func setEliteEnabled(_ on: Bool) {
        if on && eliteValue == 0 {
            eliteValue = 2
        }
        eliteEnabled = on
    }

    mutating func setEliteValue(_ value: Int) {
        eliteValue = value
        eliteEnabled = value > 0
    }

    mutating func setLevelEnabled(_ on: Bool) {
        if on && levelValue == 0 {
            levelValue = 7
        }
        levelEnabled = on
    }

    mutating func setLevelValue(_ value: Int) {
        levelValue = value
        levelEnabled = value > 0
        // 专精前置为 7 级：设定 2–6 级目标时专精不共存，专精值归零
        // （对齐 WPF MainSkillLevel setter——值清零而非仅取消勾选，重新勾选自动得专 3）。
        if value > 0 && value < 7 {
            for skill in 0..<3 {
                masteryEnabled[skill] = false
                masteryValues[skill] = 0
            }
        }
    }

    mutating func setMasteryEnabled(_ skill: Int, _ on: Bool) {
        if on && masteryValues[skill] == 0 {
            // 勾选且未选档位：自动设为专 3（经 setMasteryValue 走补足等级的规则）。
            setMasteryValue(skill, 3)
            return
        }
        masteryEnabled[skill] = on
    }

    mutating func setMasteryValue(_ skill: Int, _ value: Int) {
        masteryValues[skill] = value
        masteryEnabled[skill] = value > 0
        // 设专精且已有技能等级目标：自动补至 7 级（等级未设定时保持不设定）。
        // 判据用勾选态而非显示值——未勾选时显示值仍是默认 7，按显示值判会把
        // 未设定的等级误补成 7（决策表 5b 边界行；对齐 WPF `MainSkillLevel != 0`）。
        if value > 0 && levelEnabled {
            levelValue = 7
        }
    }

    /// 取消勾选 = 该维度目标归 0（写回配置时不带该键）；超出技能数的专精行不参与写回。
    func writeBack(into plan: inout OperProgressPlan, skillCount: Int) {
        plan.elite = eliteEnabled ? eliteValue : 0
        plan.skillLevel = levelEnabled ? levelValue : 0
        plan.skillMastery = (0..<3).map { skill in
            (masteryEnabled[skill] && skill < skillCount) ? masteryValues[skill] : 0
        }
    }
}
