//
//  DecisionTableTests.swift
//  OperProgressTests
//
//  决策表单元测试（goal-0729d7 测试骨架）：对拍
//  调查/干员培养复刻-WPF正本-1002/测试夹具/decision-table.md 全部 54 行。
//  互斥规则直调 A 步抽出的 OperProgressPlanEditor / OperProgressCallbackConsumer；
//  Mac 对应物在 View/ViewModel 编排层的行以「等价断言」或显式标注覆盖；
//  失败/边界分支合成用例标注 synthetic。
//

import XCTest
@testable import MAA

final class DecisionTableTests: XCTestCase {
    // MARK: - 覆盖清单（54 行逐条登记处置，防测试演化时丢行）

    /// 行号 →（决策表规则名，处置方式）。处置三档：
    /// direct=抽出模型直测；equivalent=对应物等价断言；layered=Mac 对应物在编排层（见各节标注）。
    static let rowManifest: [(row: Int, name: String, handling: String)] = [
        (1, "5a 等级 1-6 清空专精", "direct"),
        (2, "5a 边界：7 级不清空", "direct"),
        (3, "5a 边界：0（---）不清空", "direct"),
        (4, "5a UI 口径注（下拉无 Lv.1，触发域 2-6）", "direct+synthetic"),
        (5, "5b 专精补等级", "direct"),
        (6, "5b 边界：等级未设不补", "direct"),
        (7, "5b 边界：取消专精不触发", "direct"),
        (8, "5c 勾选自动专3", "direct"),
        (9, "5c 边界：已有值保留（5a 清零后重勾得专3）", "direct"),
        (10, "5d 未勾选按 0 产出", "direct"),
        (11, "构造器初始化勾选态", "direct"),
        (12, "精英化联动勾选", "direct"),
        (13, "阿米娅本体恒 3 技能", "direct"),
        (14, "阿米娅近卫/医疗形态 2 技能", "direct"),
        (15, "稀有度→技能数：6 星", "direct"),
        (16, "同：5/4 星", "direct"),
        (17, "同：3 星", "direct"),
        (18, "同：其余", "direct"),
        (19, "数据未命中回退（SkillCount=3）", "direct+synthetic"),
        (20, "专精行按技能数收缩", "direct"),
        (21, "role Unknown 补全", "synthetic（hostless 无干员数据，测近邻分支）"),
        (22, "三形态不可选", "direct+synthetic"),
        (23, "未知键忽略", "direct"),
        (24, "role 解析失败按名补", "synthetic（hostless 无干员数据，测近邻分支）"),
        (25, "仍未知或无名 → 整次中止", "direct"),
        (26, "非法 JSON → 中止", "direct"),
        (27, "根节点必须是数组", "direct"),
        (28, "mastery 短数组补零", "direct"),
        (29, "mastery 非数组", "direct（Mac 有意收紧：报错而非静默全零，注释记录差异）"),
        (30, "elite/skill_level 缺失 → 0", "direct"),
        (31, "导入为追加", "equivalent（拼接语义）"),
        (32, "导入条目 ShowRole=false", "layered（Mac 无 ShowRole 字段；黄金对拍证不进协议）"),
        (33, "默认目标三件套", "equivalent+synthetic（构造等价物）"),
        (34, "ShowRole 继承同名判定", "layered（Mac 以 hasSameName 实现同语义）"),
        (35, "追加与重索引", "equivalent+synthetic（数组序语义）"),
        (36, "空选择 no-op", "layered（View 层 guard）"),
        (37, "添加即落配置", "layered（VM CollectionChanged）"),
        (38, "空计划不 append", "direct（MAATask.isEmptyConfiguration）"),
        (39, "taskId>0 分支", "layered（Maa.swift 编排）"),
        (40, "taskId=null 分支", "layered（Maa.swift 编排）"),
        (41, "taskId 其他值", "layered（Maa.swift 编排）"),
        (42, "清空列表即写空配置", "layered（VM 持久化）"),
        (43, "Summary 移除判据（全维度清零非 success 计数）", "direct"),
        (44, "刷新期抑制回写", "layered（VM _isRefreshing 对应物）"),
        (45, "消息过滤（非 OperProgress 忽略）", "direct（回放族证）"),
        (46, "Detail 计划匹配（role+name → name 回退）", "direct"),
        (47, "达成清零：精英化", "direct"),
        (48, "达成清零：技能等级", "direct"),
        (49, "达成清零：专精逐位", "direct"),
        (50, "回调键缺失 = 未报告", "direct"),
        (51, "写回不刷 UI", "layered（VM：刷新统一在 Summary 后）"),
        (52, "Summary 处理", "direct（回放族证移除+保留）"),
        (53, "Detail 日志格式", "layered（VM 日志）"),
        (54, "result/status 词条化", "layered（VM 日志）"),
    ]

    func testRowManifestCoversAll54Rows() {
        XCTAssertEqual(Self.rowManifest.count, 54, "决策表 54 行应逐行登记")
        XCTAssertEqual(Set(Self.rowManifest.map(\.row)), Set(1...54), "行号应为 1...54 无缺漏")
    }

    // MARK: - A 节 等级↔专精互斥（行 1-12）

    /// 行 1：等级设 1-6（值有变化）→ 专精全 0、勾选连带 false、等级勾选 true。
    func testRow1_LevelInClearWindowClearsMastery() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", elite: 2, skillLevel: 7, skillMastery: [3, 3, 3]))
        editor.setLevelValue(5)
        XCTAssertEqual(editor.masteryValues, [0, 0, 0], "5a：专精值应全部置 0")
        XCTAssertEqual(editor.masteryEnabled, [false, false, false], "5a：勾选态连带 false")
        XCTAssertTrue(editor.levelEnabled, "IsMainSkillLevelSelected 应为 true")
        XCTAssertEqual(editor.levelValue, 5)
    }

    /// 行 2：边界 7 级不清空。
    func testRow2_Level7DoesNotClearMastery() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", skillLevel: 7, skillMastery: [3, 3, 3]))
        editor.setLevelValue(7)
        XCTAssertEqual(editor.masteryValues, [3, 3, 3], "7 级与专精可共存")
    }

    /// 行 3：边界 0（---）不清空，仅勾选 false。
    func testRow3_Level0DoesNotClearMastery() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", skillLevel: 7, skillMastery: [3, 3, 3]))
        editor.setLevelValue(0)
        XCTAssertEqual(editor.masteryValues, [3, 3, 3])
        XCTAssertFalse(editor.levelEnabled, "0（---）仅取消勾选")
    }

    /// 行 4（synthetic）：UI 下拉无 Lv.1，但 setter 触发域为 1-6——
    /// 合成输入 1（UI 不可达）验证 setter 全触发域。
    func testRow4_SyntheticLevel1ClearsMastery() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", skillLevel: 7, skillMastery: [3, 3, 3]))
        editor.setLevelValue(1)
        XCTAssertEqual(editor.masteryValues, [0, 0, 0], "synthetic：setter 触发域含 UI 不可达的 1")
    }

    /// 行 5：专精补等级——设专精 >0 且等级已设 → 等级补至 7。
    func testRow5_MasteryFillsLevelTo7() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", skillLevel: 5, skillMastery: [0, 0, 0]))
        editor.setMasteryValue(1, 2)
        XCTAssertEqual(editor.levelValue, 7, "5b：已有等级目标时设专精自动补 7")
        XCTAssertTrue(editor.levelEnabled)
    }

    /// 行 6：边界——等级未设（勾选 false）时设专精，等级保持未设。
    /// （修复验证：抽取前 Mac 实现以显示值 7 判「已有目标」误补；对齐 WPF 后按勾选态判。）
    func testRow6_MasteryDoesNotFillUnsetLevel() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", skillLevel: 0, skillMastery: [0, 0, 0]))
        XCTAssertFalse(editor.levelEnabled)
        editor.setMasteryValue(0, 3)
        XCTAssertFalse(editor.levelEnabled, "5b 边界：等级未设定时保持不设定")
        var plan = OperProgressPlan(role: .warrior, name: "陈")
        editor.writeBack(into: &plan, skillCount: 3)
        XCTAssertEqual(plan.skillLevel, 0, "写回不含 skill_level（序列化无该键）")
    }

    /// 行 7：取消专精（设 0）不触发补等级。
    func testRow7_UnsettingMasteryDoesNotTouchLevel() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", skillLevel: 5, skillMastery: [3, 0, 0]))
        editor.setMasteryValue(0, 0)
        XCTAssertEqual(editor.levelValue, 5, "取消专精不动等级")
    }

    /// 行 8：勾选且未选档位 → 自动专 3。
    func testRow8_EnableMasteryAutoFills3() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", skillMastery: [0, 0, 0]))
        editor.setMasteryEnabled(2, true)
        XCTAssertEqual(editor.masteryValues[2], 3, "5c：勾选自动设专 3")
        XCTAssertTrue(editor.masteryEnabled[2])
    }

    /// 行 9：勾选时已有值保留；5a 清零后重勾 → 得专 3。
    func testRow9_EnableMasteryKeepsExistingValue() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", skillMastery: [2, 0, 0]))
        editor.setMasteryEnabled(0, true)
        XCTAssertEqual(editor.masteryValues[0], 2, "已有值 >0 时勾选保留原值")

        // 5a 清零后重勾 → 专 3（决策表括号例）
        editor.setLevelValue(5)
        XCTAssertEqual(editor.masteryValues[0], 0)
        editor.setMasteryEnabled(0, true)
        XCTAssertEqual(editor.masteryValues[0], 3, "5a 清零后重勾自动得专 3")
    }

    /// 行 10：未勾选维度写回按 0 产出（5d）。
    func testRow10_UncheckedDimensionsWriteZero() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", elite: 2, skillLevel: 7, skillMastery: [3, 3, 3]))
        editor.setEliteEnabled(false)
        editor.setLevelEnabled(false)
        editor.setMasteryEnabled(0, false)
        // 勾选取消后目标值保留在编辑态（2/7/3），写回按 0
        var plan = OperProgressPlan(role: .warrior, name: "陈")
        editor.writeBack(into: &plan, skillCount: 3)
        XCTAssertEqual(plan.elite, 0)
        XCTAssertEqual(plan.skillLevel, 0)
        XCTAssertEqual(plan.skillMastery, [0, 3, 3])
    }

    /// 行 11：从配置加载时各勾选态 = 对应值 > 0。
    func testRow11_InitializerSetsSelectionFromValues() {
        let editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", elite: 2, skillLevel: 0, skillMastery: [0, 3, 0]))
        XCTAssertTrue(editor.eliteEnabled)
        XCTAssertFalse(editor.levelEnabled)
        XCTAssertEqual(editor.masteryEnabled, [false, true, false])
    }

    /// 行 12：精英化设 0 → 勾选联动 false。
    func testRow12_EliteZeroUnselects() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .warrior, name: "陈", elite: 2))
        editor.setEliteValue(0)
        XCTAssertFalse(editor.eliteEnabled, "Elite 设 0 → IsEliteSelected=false")
    }

    // MARK: - B 节 阿米娅三形态与技能数（行 13-22）

    private func oper(id: String, rarity: Int, role: OperProgressRole = .caster) -> OperProgressOperator {
        OperProgressOperator(
            id: id, name: "测试", displayName: "测试", role: role,
            rarity: rarity, hasSameName: false)
    }

    /// 行 13：阿米娅本体 5 星但恒 3 技能（ID 特判）。
    func testRow13_AmiyaBaseHas3Skills() {
        XCTAssertEqual(oper(id: "char_002_amiya", rarity: 5).skillCount, 3)
    }

    /// 行 14：近卫/医疗形态（rarity=5，无 ID 特判）→ 2 技能。
    func testRow14_AmiyaGuardianMedicFormsHave2Skills() {
        XCTAssertEqual(oper(id: "char_1001_amiya2", rarity: 5).skillCount, 2)
        XCTAssertEqual(oper(id: "char_1037_amiya3", rarity: 5).skillCount, 2)
    }

    /// 行 15-18：稀有度 → 技能数。
    func testRow15to18_SkillCountByRarity() {
        XCTAssertEqual(oper(id: "x6", rarity: 6).skillCount, 3, "6 星 3 技能")
        XCTAssertEqual(oper(id: "x5", rarity: 5).skillCount, 2, "5 星 2 技能")
        XCTAssertEqual(oper(id: "x4", rarity: 4).skillCount, 2, "4 星 2 技能")
        XCTAssertEqual(oper(id: "x3", rarity: 3).skillCount, 1, "3 星 1 技能")
        XCTAssertEqual(oper(id: "x2", rarity: 2).skillCount, 0, "其余无技能")
        XCTAssertEqual(oper(id: "x1", rarity: 1).skillCount, 0)
    }

    /// 行 19（synthetic）：数据未命中 → 查无返回 nil（View 层回退 SkillCount=3、
    /// DisplayName 用原名——`?? 3`/`?? plan.name` 在 OperProgressSettingsView）。
    func testRow19_SyntheticDirectoryMissFallsBack() {
        let empty = OperProgressOperatorDirectory.Directory.empty
        XCTAssertNil(empty.findOperator(named: "查无干员", role: nil), "未命中 → nil（View 层回退 3）")
    }

    /// 行 20：专精行按技能数收缩——SkillCount=2 时第三位产出 0（数值保留在编辑态）。
    func testRow20_MasteryRowsShrinkBySkillCount() {
        var editor = OperProgressPlanEditor(plan: OperProgressPlan(
            role: .support, name: "梓兰", skillMastery: [3, 3, 3]))
        var plan = OperProgressPlan(role: .support, name: "梓兰")
        editor.writeBack(into: &plan, skillCount: 2)
        XCTAssertEqual(plan.skillMastery, [3, 3, 0], "第三位按 5d 产出 0")
        XCTAssertEqual(editor.masteryValues[2], 3, "数值保留在编辑态（仅 UI 禁用+产出裁剪）")
    }

    /// 行 21（synthetic 近邻）：role 非法 → 按名反查目录；hostless 测试环境无
    /// battle_data.json（目录空）→ 反查失败 → 整单中止。正向补全分支需干员数据资源，
    /// 本 target 不覆盖（见报告遗留）。
    func testRow21_SyntheticInvalidRoleFallsBackToDirectory() throws {
        XCTAssertThrowsError(
            try OperProgressPlanParser.parse(#"[{"role":"Bogus","name":"测试","elite":2}]"#)
        ) { error in
            XCTAssertTrue(
                error is OperProgressParseError,
                "role 非法且目录反查失败应报错（近邻分支）")
        }
    }

    /// 行 22：三形态屏蔽集合（可选择列表剔除；剪贴板导入路径不受限）。
    func testRow22_BlockedAmiyaForms() {
        XCTAssertEqual(
            OperProgressOperatorDirectory.blockedIDs,
            ["char_002_amiya", "char_1001_amiya2", "char_1037_amiya3"])
    }

    // MARK: - C 节 剪贴板解析（行 23-32）

    /// 行 23：未知键忽略（parity-8 语义）。
    func testRow23_UnknownKeysIgnored() throws {
        let plans = try OperProgressPlanParser.parse(
            #"[{"role":"Warrior","name":"陈","elite":2,"extra_key":123,"nested":{"a":1}}]"#)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].name, "陈")
        XCTAssertEqual(plans[0].elite, 2)
    }

    /// 行 24（synthetic 近邻）：role 缺失 → 按名反查；hostless 无数据资源 → 报错。
    /// 正向补全分支不覆盖（同行 21 遗留）。
    func testRow24_SyntheticMissingRoleFallsBackToDirectory() {
        XCTAssertThrowsError(try OperProgressPlanParser.parse(#"[{"name":"陈","elite":2}]"#))
    }

    /// 行 25：无名 / 仍未知 → 整次中止（不部分导入）。
    func testRow25_MissingNameAborts() {
        XCTAssertThrowsError(
            try OperProgressPlanParser.parse(
                ##"[{"role":"Warrior","name":"  "},{"role":"Warrior","name":"陈"}]"##)
        ) { error in
            guard case OperProgressParseError.invalidItem(let index, _) = error else {
                return XCTFail("应为 invalidItem")
            }
            XCTAssertEqual(index, 1, "第 1 项缺干员名即报错，第 2 项不再消费")
        }
    }

    /// 行 26：非法 JSON → 中止。
    func testRow26_InvalidJSONAborts() {
        XCTAssertThrowsError(try OperProgressPlanParser.parse("not a json"))
    }

    /// 行 27：根节点必须是数组（单个对象判失败）。
    func testRow27_RootMustBeArray() {
        XCTAssertThrowsError(try OperProgressPlanParser.parse(#"{"role":"Warrior","name":"陈"}"#)) { error in
            guard case OperProgressParseError.notArray = error else {
                return XCTFail("根节点非数组应为 notArray")
            }
        }
    }

    /// 行 28：mastery 短数组补零至 3 位。
    func testRow28_ShortMasteryPadsZero() throws {
        let plans = try OperProgressPlanParser.parse(
            #"[{"role":"Warrior","name":"陈","skill_mastery":[3]}]"#)
        XCTAssertEqual(plans[0].skillMastery, [3, 0, 0])
    }

    /// 行 29：mastery 类型非数组——Mac 有意收紧为报错（WPF 静默全零，见注释与报告）；
    /// 缺失分支与 WPF 一致（全零）。
    func testRow29_MasteryNonArrayRejected() {
        XCTAssertThrowsError(try OperProgressPlanParser.parse(
            #"[{"role":"Warrior","name":"陈","skill_mastery":"x"}]"#))
    }

    func testRow29_MasteryMissingMeansAllZero() throws {
        let plans = try OperProgressPlanParser.parse(#"[{"role":"Warrior","name":"陈"}]"#)
        XCTAssertEqual(plans[0].skillMastery, [0, 0, 0], "缺失 → 全零（与 WPF 一致）")
    }

    /// 行 30：elite/skill_level 缺失 → 0。
    func testRow30_MissingNumericKeysMeanZero() throws {
        let plans = try OperProgressPlanParser.parse(#"[{"role":"Warrior","name":"陈"}]"#)
        XCTAssertEqual(plans[0].elite, 0)
        XCTAssertEqual(plans[0].skillLevel, 0)
    }

    /// 行 31（equivalent）：导入为追加——解析结果拼接在现有计划尾部（View 层
    /// `config.plans.append(contentsOf:)` 的语义前提）。
    func testRow31_ImportAppends() throws {
        let existing = [OperProgressPlan(role: .warrior, name: "陈", elite: 2)]
        let parsed = try OperProgressPlanParser.parse(
            #"[{"role":"Medic","name":"凯尔希","skill_mastery":[0,1,0]}]"#)
        let combined = existing + parsed
        XCTAssertEqual(combined.map(\.name), ["陈", "凯尔希"], "追加非替换")
    }

    // 行 32（layered）：Mac 无 ShowRole 字段——不进协议（黄金对拍 case 输入含
    // show_role、期望输出无此键，黄金族已证）；同名职业后缀由 hasSameName 表达。

    // MARK: - D 节 添加干员默认目标（行 33-37）

    /// 行 33（equivalent+synthetic）：添加的默认目标三件套
    /// （OperProgressSettingsView.addOperator 的字面构造）。
    func testRow33_SyntheticDefaultPlanTriple() {
        let plan = OperProgressPlan(
            role: .warrior, name: "陈", elite: 2, skillLevel: 7, skillMastery: [3, 3, 3])
        XCTAssertEqual(plan.elite, 2)
        XCTAssertEqual(plan.skillLevel, 7)
        XCTAssertEqual(plan.skillMastery, [3, 3, 3])
    }

    /// 行 35（equivalent+synthetic）：追加至尾部、序号按位置连续（ReindexPlanItems 语义）。
    func testRow35_SyntheticAppendAndIndex() {
        var plans = [OperProgressPlan(role: .warrior, name: "陈")]
        plans.append(OperProgressPlan(role: .medic, name: "凯尔希"))
        XCTAssertEqual(plans.firstIndex { $0.name == "凯尔希" }, 1, "Index=当时 Count")
        XCTAssertEqual(
            plans.enumerated().map { offset, _ in offset + 1 },
            [1, 2],
            "集合变更后序号重排为连续")
    }

    // 行 34/36/37（layered）：ShowRole 继承（Mac 以 hasSameName 表达）、空选择 no-op
    //（View guard selectedOperator == nil）、添加即落配置（VM CollectionChanged）——
    // 均在编排层，不在本 target 直测范围。

    // MARK: - E 节 空计划行为（行 38-44）

    /// 行 38：空计划不 append（MAATask.isEmptyConfiguration）。
    func testRow38_EmptyPlansNotAppended() {
        XCTAssertTrue(MAATask.operProgress(OperProgressConfiguration()).isEmptyConfiguration)
        XCTAssertFalse(
            MAATask.operProgress(
                OperProgressConfiguration(plans: [OperProgressPlan(role: .warrior, name: "陈")])
            ).isEmptyConfiguration)
    }

    /// 行 43：Summary 移除判据=全维度清零（非 success 计数）。
    func testRow43_RemovalRequiresAllDimensionsZero() {
        let finished = OperProgressPlan(role: .warrior, name: "陈")  // 全零
        let remaining = OperProgressPlan(role: .warrior, name: "凯尔希", skillMastery: [0, 3, 3])
        let result = OperProgressCallbackConsumer.removingFinishedPlans(from: [finished, remaining])
        XCTAssertEqual(result.map(\.name), ["凯尔希"], "仅移除全维度清零条目")
    }

    /// 行 43 关键实证：success=3、finished 有快照，但计划 [0,3,3] 只达成 [0,1,0]
    /// → 清零后 [0,3,3] 非全零 → 保留。「finished 是达成态快照非移除指令」。
    func testRow43_FinishedSnapshotIsNotRemovalOrder() {
        var plan = OperProgressPlan(role: .warrior, name: "克莱门莎", elite: 2, skillLevel: 7, skillMastery: [0, 3, 3])
        let outcome = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "克莱门莎", elite: 2, skillLevel: nil, skillMastery: [0, 1, 0]),
            in: [plan])
        plan = outcome.plans[0]
        XCTAssertEqual(plan.elite, 0)
        XCTAssertEqual(plan.skillMastery, [0, 3, 3], "只清达成位（1<3 不清）")
        let after = OperProgressCallbackConsumer.removingFinishedPlans(from: [plan])
        XCTAssertEqual(after.count, 1, "非全维度清零 → Summary 后保留（无视 success 计数）")
    }

    // 行 39-42/44（layered）：taskId 三分支（Maa.swift 编排）、清空写空配置（VM）、
    // 刷新期抑制回写（VM _isRefreshing 对应物）——不在本 target 直测范围。

    // MARK: - F 节 回调消费（行 45-54）

    /// 行 46：先按 role+name 精确匹配，未命中按 name 回退。
    func testRow46_DetailPlanMatching() {
        let plans = [
            OperProgressPlan(role: .caster, name: "阿米娅"),
            OperProgressPlan(role: .warrior, name: "阿米娅"),
        ]
        // role+name 精确命中第二个
        let precise = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "阿米娅", elite: 2, skillLevel: nil, skillMastery: nil),
            in: plans)
        XCTAssertEqual(precise.matchedIndex, 1)

        // role 非法（回退 nil）→ 按 name 命中第一个（WPF 即此行为，含同名错配可能）
        let fallback = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Bogus", name: "阿米娅", elite: 2, skillLevel: nil, skillMastery: nil),
            in: plans)
        XCTAssertEqual(fallback.matchedIndex, 0)

        // 无匹配 → matchedIndex nil（调用方记日志后忽略）
        let none = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "查无此人", elite: 2, skillLevel: nil, skillMastery: nil),
            in: plans)
        XCTAssertNil(none.matchedIndex)
        XCTAssertEqual(none.plans.count, 2)
        XCTAssertFalse(none.modified)
    }

    /// 行 47：精英化达成清零（callback.elite ≥ plan.elite）。
    func testRow47_EliteAchievedClears() {
        let outcome = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "陈", elite: 2, skillLevel: nil, skillMastery: nil),
            in: [OperProgressPlan(role: .warrior, name: "陈", elite: 2)])
        XCTAssertEqual(outcome.plans[0].elite, 0)
        XCTAssertTrue(outcome.modified)
    }

    /// 行 47 边界（synthetic）：未达成（2 < 3）不清零。
    func testRow47_SyntheticEliteNotAchievedKeeps() {
        let outcome = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "陈", elite: 2, skillLevel: nil, skillMastery: nil),
            in: [OperProgressPlan(role: .warrior, name: "陈", elite: 3)])
        XCTAssertEqual(outcome.plans[0].elite, 3)
        XCTAssertFalse(outcome.modified)
    }

    /// 行 48：技能等级达成清零。
    func testRow48_SkillLevelAchievedClears() {
        let outcome = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "陈", elite: nil, skillLevel: 7, skillMastery: nil),
            in: [OperProgressPlan(role: .warrior, name: "陈", skillLevel: 7)])
        XCTAssertEqual(outcome.plans[0].skillLevel, 0)
        XCTAssertTrue(outcome.modified)
    }

    /// 行 49：专精逐位达成清零（全清/部分清均直接存数组）。
    func testRow49_MasteryAchievedClearsPerSkill() {
        let outcome = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "陈", elite: nil, skillLevel: nil, skillMastery: [3, 1, 0]),
            in: [OperProgressPlan(role: .warrior, name: "陈", skillMastery: [3, 3, 3])])
        XCTAssertEqual(outcome.plans[0].skillMastery, [0, 3, 3], "第 1 位 3≥3 清零；第 2 位 1<3 不清；第 3 位 0<3 不清")
        XCTAssertTrue(outcome.modified)
    }

    /// 行 50：回调键缺失 = 未报告——对应维度不参与比对、计划不动。
    func testRow50_MissingKeysMeanNotReported() {
        let outcome = OperProgressCallbackConsumer.consumeDetail(
            OperProgressCallbackSnapshot(role: "Warrior", name: "陈", elite: nil, skillLevel: nil, skillMastery: nil),
            in: [OperProgressPlan(role: .warrior, name: "陈", elite: 2, skillLevel: 7, skillMastery: [3, 3, 3])])
        XCTAssertEqual(outcome.plans[0].elite, 2)
        XCTAssertEqual(outcome.plans[0].skillLevel, 7)
        XCTAssertEqual(outcome.plans[0].skillMastery, [3, 3, 3])
        XCTAssertFalse(outcome.modified)
    }

    // 行 45/52：消息过滤与 Summary 处理由回放族实证（CallbackReplayTests：
    // 50 条混入消息仅 3 Detail + 1 Summary 被消费）；行 51/53/54（写回不刷 UI、
    // 日志格式、词条化）在 VM 层，不在本 target 直测范围。
}
