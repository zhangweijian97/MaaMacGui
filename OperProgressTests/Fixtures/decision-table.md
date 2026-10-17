# 干员培养互斥/解析决策表（WPF 正本语义照抄）

> 2026-10-17 提炼。**纯 WPF 语义，不含任何 Mac 侧实现判断**。
> 行号出处（本目录文件）：`PlanItemVM` = OperProgressPlanItemViewModel.cs，`UCModel` = OperProgressTaskUserControlModel.cs，`AsstTask` = AsstOperProgressTask.cs，`词条` = zh-cn-词条.txt。
> 「值有变化」指 WPF `SetAndNotify` 语义：赋同值不触发副作用。

## A. 等级↔专精互斥（5a/5b/5c/5d）

| 规则名 | WPF 行号出处 | 输入 | 期望输出 |
|---|---|---|---|
| 5a 等级 1-6 清空专精 | PlanItemVM:151-156 | `MainSkillLevel` 设为 v（1≤v≤6），值有变化 | SpecializationSkill1/2/3 全部置 0；连带三个 IsSpecializationSkillNSelected=false（经 SetSpecializationTarget 的 `IsSelected = value>0`，PlanItemVM:250-261）；IsMainSkillLevelSelected=true |
| 5a 边界：7 级不清空 | PlanItemVM:151 | `MainSkillLevel` 设为 7 | 专精值不动（等级 7 与专精可共存） |
| 5a 边界：0（---）不清空 | PlanItemVM:151,157 | `MainSkillLevel` 设为 0 | 专精值不动；仅 IsMainSkillLevelSelected=false |
| 5a UI 口径注 | UCModel:434-442 | 下拉 MainSkillLevelList | 可选值 0("---"),2,3,4,5,6,7——**无 Lv.1**；UI 实际能触发 5a 的输入是 2-6 |
| 5b 专精补等级 | PlanItemVM:246-249 | 任一 `SpecializationSkillN` 设为 >0（值有变化）且 MainSkillLevel≠0 | MainSkillLevel=7 |
| 5b 边界：等级未设不补 | PlanItemVM:246 | 设专精 >0 且 MainSkillLevel==0 | MainSkillLevel 保持 0（后续序列化无 skill_level 键） |
| 5b 边界：取消专精不触发 | PlanItemVM:246 | `SpecializationSkillN` 设为 0 | 不动 MainSkillLevel |
| 5c 勾选自动专3 | PlanItemVM:173-176 / 187-190 / 201-204 | `IsSpecializationSkillNSelected` false→true 且当前值==0 | SpecializationSkillN=3 |
| 5c 边界：已有值保留 | 同上 | 勾选 true 且当前值>0 | 值不变（例：5a 清零后重勾 → 得专3） |
| 5d 未勾选按 0 产出 | PlanItemVM:226 + UCModel:82-84 | SavePlan 时任一维度勾选态=false | 该维度按 0 写入配置：`IsEliteSelected?Elite:0`、`IsMainSkillLevelSelected?MainSkillLevel:0`、专精逐位 `IsSelected?值:0`（getter 裁剪） |
| 构造器初始化勾选态 | PlanItemVM:47-56 | 从配置加载（elite, mainSkillLevel, mastery[3]） | 各 Is*Selected = 对应值 > 0（专精逐位） |
| 精英化联动勾选 | PlanItemVM:123-134 | `Elite` 设为 0 | IsEliteSelected=false；EliteList 的 0 显示为 "---"（UCModel:428-432）；可选项仅 0/1/2 |

## B. 阿米娅三形态与技能数

| 规则名 | WPF 行号出处 | 输入 | 期望输出 |
|---|---|---|---|
| 阿米娅本体恒 3 技能 | PlanItemVM:68-71 | 解析命中 `char_002_amiya` | SkillCount=3（ID 特判，不看稀有度） |
| 阿米娅近卫/医疗形态 2 技能 | PlanItemVM:72-79 | 解析命中 `char_1001_amiya2` / `char_1037_amiya3`（rarity=5，无 ID 特判） | SkillCount=2 |
| 稀有度→技能数：6 星 | PlanItemVM:74-79 | rarity 6 | SkillCount=3 |
| 同：5/4 星 | 同上 | rarity 5 或 4 | SkillCount=2 |
| 同：3 星 | 同上 | rarity 3 | SkillCount=1 |
| 同：其余 | 同上 | rarity ≤2 等 | SkillCount=0 |
| 数据未命中回退 | PlanItemVM:85-90 | 按 role+name 查不到干员 | SkillCount=3 + Warning 日志；OperId=null（头像 null）；DisplayName 用原名 |
| 专精行按技能数收缩 | PlanItemVM:81-83 | SkillCount=2 且载入数据第三位勾选 | IsSpecializationSkill3Selected 强制 false（SpecializationSkill3 数值保留，但按 5d 产出为 0）；SkillCount=1 时第 2/3 位同裁 |
| role Unknown 补全 | PlanItemVM:59-67 | role=Unknown 且按名查到干员 | Role ← oper.Role（查找条件：`role==Unknown 或 c.Role==role` 且同名，取首个） |
| 三形态不可选 | UCModel:95-96 | 干员下拉列表 OperatorNames | 过滤 char_002_amiya / char_1001_amiya2 / char_1037_amiya3（注释：培养流程未验证前不可选；剪贴板导入路径仍可达上两条规则） |

## C. 剪贴板解析与未知键容差

| 规则名 | WPF 行号出处 | 输入 | 期望输出 |
|---|---|---|---|
| 未知键忽略 | UCModel:376-395 | plan JSON 含五白名单键（role/name/elite/skill_level/skill_mastery）以外的键 | 仅读白名单键，未知键静默忽略，正常导入 |
| role 解析失败按名补 | UCModel:170-173 | role 缺失或不是 OperatorRole 枚举名 | Role=Unknown 后按 Name 在 Operators 里找首个同名词补全 Role |
| 仍未知或无名 → 整次中止 | UCModel:174-178 | 任一条目 Role 仍 Unknown 或 Name 为空 | AddLog(ParseFailed + `unknown oper: {role}-{name}`) 后 return；**整批不写回**（含此前已解析成功的条目），现有计划不变 |
| 非法 JSON → 中止 | UCModel:184-188 | 剪贴板文本 JArray.Parse 抛异常 | AddLog(ParseFailed + 异常消息)，现有计划不变 |
| 根节点必须是数组 | UCModel:165 | 剪贴板文本（先 Trim） | 必须能 `JArray.Parse`；单个对象（非数组）判失败 |
| mastery 短数组补零 | UCModel:384-391 | skill_mastery 数组长度 <3 | 右侧补 0 至 3 位 |
| mastery 非数组 → 全零 | UCModel:383-392,179 | skill_mastery 缺失或类型非数组 | SkillMastery=null → 存 Of(0,0,0) |
| elite/skill_level 缺失 → 0 | UCModel:179 | 键缺失（`Value<int?>` 得 null） | 存 0 |
| 导入为追加 | UCModel:166,181 | 任意合法导入 | 追加到现有 Plans 尾部（非替换），写回后 RefreshUI |
| 导入条目 ShowRole=false | UCModel:179 | — | 新条目 ShowRole=false（卡片不显示职业后缀） |

## D. 添加干员默认目标

| 规则名 | WPF 行号出处 | 输入 | 期望输出 |
|---|---|---|---|
| 默认目标三件套 | UCModel:202 | 点添加（OperSelect 非空） | 新条目 elite=2、skill_level=7、mastery=[3,3,3]、IsExpanded=true |
| ShowRole 继承同名判定 | UCModel:202 | 同 | ShowRole=HasSameRoleOpers（同名多职业干员卡片显示职业后缀） |
| 追加与重索引 | UCModel:202, 256-262 | 同 | 追加至列表尾（Index=当时 Count）；集合变更后 ReindexPlanItems 重排为连续序号 |
| 空选择 no-op | UCModel:197-200 | OperSelect=null | 不添加任何条目 |
| 添加即落配置 | UCModel:217-231 | PlanItems.Add 触发 CollectionChanged（非刷新期） | ReindexPlanItems + SavePlan 写回任务配置 |

## E. 空计划行为

| 规则名 | WPF 行号出处 | 输入 | 期望输出 |
|---|---|---|---|
| 空计划不 append | UCModel:273-276 | Plans.Count==0 时 SerializeTask | 返回 (null, [])：不向 core 追加任务、不设参数 |
| taskId>0 分支 | UCModel:279-280 | taskId>0 且计划非空 | `AsstSetTaskParamsEncoded(id, task)` 更新既有任务 |
| taskId=null 分支 | UCModel:281 | taskId=null 且计划非空 | `AsstAppendTaskWithEncoding` 新增任务 |
| taskId 其他值 | UCModel:282-283 | taskId≤0 等 | (null, []) no-op |
| 清空列表即写空配置 | UCModel:151-154 + 217-231 | ClearPlan()（非刷新期） | PlanItems 清空 → CollectionChanged → SavePlan 写 Plans=[]（随后命中「空计划不 append」） |
| Summary 移除判据 | UCModel:133-141 | RemoveFinishedPlans(taskId) | 仅移除 `elite==0 && skill_level==0 && mastery 全 0` 的条目（全维度清零，**非 success 计数**）；配置本来就空则直接 return（不刷新 UI） |
| 刷新期抑制回写 | UCModel:61,112-115,224-227,235 | _isRefreshing=true 期间 | 集合变更/属性变更不触发 SavePlan（防止刷新期间把条目回写配置） |

## F. 回调消费（Detail/Summary）

| 规则名 | WPF 行号出处 | 输入 | 期望输出 |
|---|---|---|---|
| 消息过滤 | UCModel:289 | 非 SubTaskExtraInfo，或 taskchain≠"OperProgress" | 忽略 |
| Detail 计划匹配 | UCModel:310-313 | 回调 (role, name) | 先按 Role+Name 精确匹配 Plans；未命中按 Name 回退；仍无匹配 → AddLog("Could not find matching plan for OperProgressDetail") 后忽略该消息 |
| 达成清零：精英化 | UCModel:321-325 | callback.elite ≥ plan.elite（键存在时） | plan.elite=0，标记 isModified |
| 达成清零：技能等级 | UCModel:326-330 | callback.skill_level ≥ plan.skill_level（键存在时） | plan.skill_level=0，标记 isModified |
| 达成清零：专精逐位 | UCModel:331-355 | callback.skill_mastery[i] ≥ plan.skill_mastery[i]（键存在时，逐位） | 该位置 0；与旧值有差异才写回（全清零/部分清零均直接存数组） |
| 回调键缺失 = 未报告 | UCModel:321,326,331 | Detail JSON 缺 elite / skill_level / skill_mastery 键 | 对应维度不参与比对、plan 不动（`int?`/`SkillMastery?` 为 null） |
| 写回不刷 UI | UCModel:356-360 | isModified=true | list[index]=plan 并写回 task.Plans；**不触发 UI 刷新**（刷新只在 Summary 后） |
| Summary 处理 | UCModel:295-304 | what=OperProgressSummary | AddLog「干员培养完成：成功 S，失败 F，跳过 K」（词条 OperProgress.Summary）；F>0 用 Warning 色否则 Info；随后 RemoveFinishedPlans(msg.TaskId)（内含 RefreshUI） |
| Detail 日志格式 | UCModel:361-369 + 词条:14 | — | 「干员培养 {序号}:{干员名} {status}」+ 换行接目标回调描述（精英化 N / 技能等级 N / 技能 N 专精 N，词条 OperProgress.EliteTarget/SkillLevelTarget/MasteryTarget）；序号=匹配后 `IndexOf(plan)+1`；干员名取本地化名（查不到用原名） |
| result/status 词条化 | UCModel:361-368 | details.result（如 "Success"） | 经 `GetStringFormat(status)` 本地化后进日志；result_detail（Completed/PrerequisiteTraining 等）不进日志 |

## 已知语义注记（WPF 行为如此，照抄；非模糊即边界）

1. **5a 触发域口径**：setter 逻辑是 1-6（PlanItemVM:151 `value > 0 && value < 7`）；parity 清单写"2-6"是 UI 下拉无 Lv.1 所致（UCModel:434-442），两者不矛盾。
2. **回调报 0 的语义**：若 core 在 Detail 里报 `elite:0`（材料内无实例，是否会发生未知），WPF 判 `0 >= plan.elite`——仅当 plan.elite=0 时成立（no-op 清零），不会错误清掉正目标。
3. **"finished" 是达成态快照，不是移除指令**：fixture-callbacks-1017.json 实证——计划 [0,3,3] 只达成 [0,1,0] 也进 finished、success 计 3；WPF 移除判据独立于 success 计数（全维度清零），该计划在 Summary 后保留。
4. **role+name 匹配的回退**：仅按 Name 回退匹配，同名多形态干员（阿米娅三形态共享基础名）时可能匹配到非目标 plan——WPF 即此行为。
