//
//  GoldenSerializationTests.swift
//  OperProgressTests
//
//  黄金序列化对拍（goal-0729d7 测试骨架）：10 组黄金输入 → OperProgressParams
//  请求构造 → JSONEncoder 序列化 → 与黄金 JSON 深比较。
//  深比较=语义比较（键序无关）——夹具头注实测同进程两次请求 JSON 键序随机，禁字节比较。
//

import XCTest
@testable import MAA

/// 测试夹具加载与深比较工具。
enum FixtureLoader {
    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)
        case malformed(String)

        var description: String {
            switch self {
            case .missing(let what):
                return "测试夹具缺失：\(what)"
            case .malformed(let what):
                return "测试夹具形态不符：\(what)"
            }
        }
    }

    static func loadJSON(_ name: String) throws -> [String: Any] {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw FixtureError.missing("\(name).json")
        }
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw FixtureError.malformed("\(name).json 根节点应为对象")
        }
        return dict
    }

    /// 语义深比较：字典按键匹配（键序无关）、数组按序、NSNumber 按值内容。
    static func deepEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (l as [String: Any], r as [String: Any]):
            guard l.count == r.count else { return false }
            return l.allSatisfy { key, value in
                guard let rv = r[key] else { return false }
                return deepEqual(value, rv)
            }
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return false }
            return zip(l, r).allSatisfy { deepEqual($0, $1) }
        case let (l as NSNumber, r as NSNumber):
            return l == r
        case let (l as String, r as String):
            return l == r
        default:
            return false
        }
    }
}

private final class BundleToken {}

final class GoldenSerializationTests: XCTestCase {
    /// 10 组黄金输入逐组对拍：输入计划 → 请求构造 → 序列化 → 深比较黄金 JSON。
    func testGoldenSerializationParity() throws {
        let fixture = try FixtureLoader.loadJSON("golden-serialization")
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]], "cases 应为数组")
        XCTAssertEqual(cases.count, 10, "黄金集应为 10 组（夹具头注）")

        for c in cases {
            let id = try XCTUnwrap(c["id"] as? Int)
            let name = try XCTUnwrap(c["name"] as? String)
            let input = try XCTUnwrap(c["input"] as? [String: Any])
            let expected = try XCTUnwrap(c["expected_outer"] as? [String: Any])

            // 黄金输入（含 show_role 等额外键）→ 计划模型
            let plansData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(input["plans"]))
            let plans = try JSONDecoder().decode([OperProgressPlan].self, from: plansData)

            // 请求构造 → 序列化（断言点：深比较，非字节比较）
            let encoded = try JSONEncoder().encode(OperProgressParams(plans: plans))
            let actual = try JSONSerialization.jsonObject(with: encoded)

            XCTAssertTrue(
                FixtureLoader.deepEqual(actual, expected),
                "case \(id)「\(name)」序列化结果与黄金不一致：actual=\(actual) expected=\(expected)")
        }
    }

    /// 键序无关性实证：同一请求用默认/排序两种编码（键序不同）深比较必等——
    /// 证明断言不依赖键序（夹具头注：同进程两次请求键序随机）。
    func testKeyOrderIndependence() throws {
        let plans = [
            OperProgressPlan(role: .warrior, name: "克莱门莎", elite: 2, skillLevel: 7, skillMastery: [0, 3, 3]),
        ]
        let defaultEncoded = try JSONEncoder().encode(OperProgressParams(plans: plans))
        let sortedEncoder = JSONEncoder()
        sortedEncoder.outputFormatting = [.sortedKeys]
        let sortedEncoded = try sortedEncoder.encode(OperProgressParams(plans: plans))

        let a = try JSONSerialization.jsonObject(with: defaultEncoded)
        let b = try JSONSerialization.jsonObject(with: sortedEncoded)
        XCTAssertTrue(FixtureLoader.deepEqual(a, b), "两种键序的序列化语义应相等")
    }

    /// 空计划序列化：外层 {"plans":[]}（「空计划不 append」的 VM 层闸是另一层语义，
    /// 此处锁定序列化层输出形态）。
    func testEmptyPlansSerialization() throws {
        let encoded = try JSONEncoder().encode(OperProgressParams(plans: []))
        let actual = try JSONSerialization.jsonObject(with: encoded)
        let expected = try JSONSerialization.jsonObject(with: Data(#"{"plans": []}"#.utf8))
        XCTAssertTrue(FixtureLoader.deepEqual(actual, expected))
    }
}
