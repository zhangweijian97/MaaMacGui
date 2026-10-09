//
//  MAATaskConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

protocol MAATaskConfiguration: Codable, Hashable, Sendable {
    var type: MAATaskType { get }

    var title: String { get }
    var subtitle: String { get }
    var summary: String { get }

    var projectedTask: MAATask { get }

    associatedtype Params: Encodable
    var params: Params { get }
}

extension MAATaskConfiguration {
    init() {
        let data = Data([0x7b, 0x7d])
        let decoder = JSONDecoder()
        self = try! decoder.decode(Self.self, from: data)
    }
}

// MARK: JSON TaskParams

extension MAAHandle {
    func appendTask(_ task: MAATask) throws -> Int32 {
        switch task {
        case .startup(let config):
            return try appendTask(config: config)
        case .closedown(let config):
            return try appendTask(config: config)
        case .recruit(let config):
            return try appendTask(config: config)
        case .infrast(let config):
            return try appendTask(config: config)
        case .fight(let config):
            return try appendTask(config: config)
        case .mall(let config):
            return try appendTask(config: config)
        case .autoRaise:
            // 自动养成只读骨架：core 无 AutoRaise 任务类型，实际下发 Depot（仓库识别），
            // 仅读取仓库库存，不改动游戏状态。
            return try appendTask(type: .Depot, params: "")
        case .award(let config):
            return try appendTask(config: config)
        case .operProgress(let config):
            // 干员培养：按上游协议下发 plans（core 侧任务注册开关未开时会返回 0 抛错，
            // 与 WPF 端同状态）。
            return try appendTask(config: config)
        case .switchTheme(let config):
            return try appendTask(config: config)
        case .roguelike(let config):
            return try appendTask(config: config)
        case .reclamation(let config):
            return try appendTask(config: config)
        }
    }

    fileprivate func appendTask<T: MAATaskConfiguration>(config: T) throws -> Int32 {
        try appendTask(type: config.type, params: config.params.jsonString())
    }
}

extension KeyedDecodingContainer {
    subscript<T: Decodable>(key: Key, default defaultValue: @autoclosure () -> T) -> T {
        (try? decode(T.self, forKey: key)) ?? defaultValue()
    }
}
