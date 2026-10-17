//
//  CallbackReplayTests.swift
//  OperProgressTests
//
//  回调回放（goal-0729d7 测试骨架）：fixture-callbacks-1017.json 的 50 条原始
//  回调体灌入 A 步抽出的回调消费逻辑（OperProgressCallbackConsumer）。
//  核心断言：Summary 移除判据=全维度清零（非 success 计数——core 的 finished
//  是达成态快照非移除指令）+ Detail 达成清零写回。
//

import XCTest
@testable import MAA

final class CallbackReplayTests: XCTestCase {
    /// 50 条消息全量回放：非 OperProgress 的消息全部忽略（含 36 条 SubTaskError、
    /// 5 条 MaterialSynthesis* 等），3 条 Detail 逐条消费，1 条 Summary 触发移除。
    func testReplayAllFiftyMessages() throws {
        let fixture = try FixtureLoader.loadJSON("fixture-callbacks-1017")
        let messages = try XCTUnwrap(fixture["messages"] as? [[String: Any]], "messages 应为数组")
        XCTAssertEqual(messages.count, 50, "回放夹具应为 50 条")

        // 初始计划来自夹具 meta.request.parsed（真实场景的请求侧输入）
        let meta = try XCTUnwrap(fixture["meta"] as? [String: Any])
        let request = try XCTUnwrap(meta["request"] as? [String: Any])
        let requestParsed = try XCTUnwrap(request["parsed"] as? [String: Any])
        let plansData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(requestParsed["plans"]))
        var plans = try JSONDecoder().decode([OperProgressPlan].self, from: plansData)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].name, "克莱门莎")
        XCTAssertEqual(plans[0].skillMastery, [0, 3, 3])

        var detailCount = 0
        var summaryCount = 0
        var ignoredCount = 0

        for message in messages {
            let parsed = try XCTUnwrap(message["parsed"] as? [String: Any])
            // 消息过滤（决策表 F-45）：非 SubTaskExtraInfo 或 taskchain≠OperProgress 忽略
            guard parsed["event"] as? String == "SubTaskExtraInfo",
                parsed["taskchain"] as? String == "OperProgress",
                let what = parsed["what"] as? String
            else {
                ignoredCount += 1
                continue
            }
            switch what {
            case "OperProgressDetail":
                let details = try XCTUnwrap(parsed["details"] as? [String: Any])
                let snapshot = OperProgressCallbackSnapshot(
                    role: details["role"] as? String,
                    name: try XCTUnwrap(details["name"] as? String),
                    elite: (details["elite"] as? NSNumber)?.intValue,
                    skillLevel: (details["skill_level"] as? NSNumber)?.intValue,
                    skillMastery: (details["skill_mastery"] as? [Any])?.map { ($0 as? NSNumber)?.intValue ?? 0 })
                let outcome = OperProgressCallbackConsumer.consumeDetail(snapshot, in: plans)
                if outcome.matchedIndex != nil {
                    plans = outcome.plans
                    detailCount += 1
                } else {
                    ignoredCount += 1
                }
            case "OperProgressSummary":
                plans = OperProgressCallbackConsumer.removingFinishedPlans(from: plans)
                summaryCount += 1
            default:
                // MaterialSynthesis* 等同链消息不消费（决策表 F-45 消息过滤）
                ignoredCount += 1
            }
        }

        // 50 条 = 3 Detail + 1 Summary + 46 忽略（SubTaskError 36 + MaterialSynthesis 5 + 链路事件 5）
        XCTAssertEqual(detailCount, 3)
        XCTAssertEqual(summaryCount, 1)
        XCTAssertEqual(ignoredCount, 46)
        XCTAssertEqual(detailCount + summaryCount + ignoredCount, 50)

        // 终态断言：三维度各自清零后的残余
        // ① 精英化 2 达成（2≥2）→ elite=0
        // ② 技能等级 7 达成（7≥7）→ skillLevel=0
        // ③ 专精 [0,1,0]：仅第 2 位 1≥3 不成立——达成度未到目标，计划 [0,3,3] 清零后仍 [0,3,3]
        XCTAssertEqual(plans.count, 1, "条目保留：专精未全清 → 非全维度清零 → 不移除")
        XCTAssertEqual(plans[0].elite, 0)
        XCTAssertEqual(plans[0].skillLevel, 0)
        XCTAssertEqual(plans[0].skillMastery, [0, 3, 3])
    }

    /// Summary 移除判据的对照实证：同夹具场景（success=3、finished 有条目快照）
    /// 条目保留；构造全维度清零的条目则被移除。移除判据与 success 计数解耦。
    func testRemovalCriterionIsAllDimensionsZeroNotSuccessCount() {
        // 夹具 Summary 实况：success=3、finished=[{elite:2,skill_level:7,skill_mastery:[0,1,0]}]
        // ——若移除判据是 success 计数或 finished 快照存在，条目会被错误移除。
        let replayed = OperProgressPlan(role: .warrior, name: "克莱门莎", elite: 0, skillLevel: 0, skillMastery: [0, 3, 3])
        XCTAssertEqual(OperProgressCallbackConsumer.removingFinishedPlans(from: [replayed]).count, 1)

        // 对照：全维度清零 → 移除
        let allZero = OperProgressPlan(role: .warrior, name: "克莱门莎")
        XCTAssertEqual(OperProgressCallbackConsumer.removingFinishedPlans(from: [allZero]).count, 0)

        // 对照：仅 skill_level 残留 → 保留
        let levelLeft = OperProgressPlan(role: .warrior, name: "克莱门莎", skillLevel: 7)
        XCTAssertEqual(OperProgressCallbackConsumer.removingFinishedPlans(from: [levelLeft]).count, 1)
    }

    /// 合成（synthetic）：Detail 无匹配计划——名字查无 → matchedIndex nil、计划不变。
    func testSyntheticDetailWithoutMatchingPlan() {
        let plans = [OperProgressPlan(role: .warrior, name: "陈", elite: 2)]
        let outcome = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "不存在的干员", elite: 2, skillLevel: nil, skillMastery: nil),
            in: plans)
        XCTAssertNil(outcome.matchedIndex, "无匹配 → 调用方记日志后忽略该消息")
        XCTAssertFalse(outcome.modified)
        XCTAssertEqual(outcome.plans.count, 1)
        XCTAssertEqual(outcome.plans[0].elite, 2)
    }

    /// 合成（synthetic）：role 回退分支——回调 role 非法（解析为 nil）时按名字匹配。
    /// 计划条目带 role 而回调 role 解析失败 → 第一段（role+name）不命中 → 第二段（name）命中。
    func testSyntheticRoleFallbackMatching() {
        let plans = [
            OperProgressPlan(role: .warrior, name: "阿米娅", elite: 1),
            OperProgressPlan(role: nil, name: "陈", elite: 2),
        ]
        // role 非法 → callbackRole=nil → 第一段要求 plan.role==nil，只匹配无 role 条目
        let bogusRole = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "NotARole", name: "陈", elite: 2, skillLevel: nil, skillMastery: nil),
            in: plans)
        XCTAssertEqual(bogusRole.matchedIndex, 1)
        XCTAssertEqual(bogusRole.plans[1].elite, 0)

        // role 缺失（nil）→ 同样走 name 回退，匹配第一个同名（或无 role）条目
        let missingRole = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: nil, name: "阿米娅", elite: 1, skillLevel: nil, skillMastery: nil),
            in: plans)
        XCTAssertEqual(missingRole.matchedIndex, 0, "role 缺失时按名字回退命中第一个同名条目（WPF 即此行为）")
    }
}
