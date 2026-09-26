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
    /// 追加一个队列条目对应的 core 任务，返回它占用的 core 任务 id 列表。
    ///
    /// 常规条目只对应一个 core 任务，返回单元素数组；「更新数据」按勾选项拆成干员识别与
    /// 仓库识别两个 core 任务；「库存保持」按需拆成仓库识别与若干理智作战，各自占一个 id。
    func appendTask(_ task: MAATask) throws -> [Int32] {
        switch task {
        case .startup(let config):
            return [try appendTask(config: config)]
        case .closedown(let config):
            return [try appendTask(config: config)]
        case .recruit(let config):
            return [try appendTask(config: config)]
        case .infrast(let config):
            return [try appendTask(config: config)]
        case .fight(let config):
            return [try appendTask(config: config)]
        case .mall(let config):
            return [try appendTask(config: config)]
        case .award(let config):
            return [try appendTask(config: config)]
        case .switchTheme(let config):
            return [try appendTask(config: config)]
        case .depotmaintain(let config):
            // 计划与缺口已在规划阶段算好：先识别库存（可选），再逐条下发作战任务
            var coreTaskIDs = [Int32]()
            if config.updateDepot {
                coreTaskIDs.append(try appendTask(type: .Depot, params: ""))
            }
            for fight in config.fights {
                coreTaskIDs.append(try appendTask(type: .Fight, params: fight.config.params.jsonString()))
            }
            return coreTaskIDs
        case .userdataupdate(let config):
            var coreTaskIDs = [Int32]()
            if config.updateOperBox {
                coreTaskIDs.append(try appendTask(type: .OperBox, params: ""))
            }
            if config.updateDepot {
                coreTaskIDs.append(try appendTask(type: .Depot, params: ""))
            }
            return coreTaskIDs
        case .roguelike(let config):
            return [try appendTask(config: config)]
        case .reclamation(let config):
            return [try appendTask(config: config)]
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
