import Foundation

// Синхронизация с сервером — модуль-заготовка «на будущее» (решение пользователя
// 31.10.2026). Локальное хранилище остаётся источником истины (§2); серверный
// бэкенд вернётся сюда реализацией протокола без изменения вызовов.

public enum SyncError: Error, CustomStringConvertible, Sendable {
    case notConfigured
    public var description: String {
        switch self {
        case .notConfigured: return "Синхронизация не подключена"
        }
    }
}

public protocol SyncService: Sendable {
    /// false = модуль-заготовка, сервер не подключён.
    var isAvailable: Bool { get }
    func push(_ data: AppData) async throws
    func pull() async throws -> AppData?
}

/// Текущая реализация: ничего не делает и честно говорит «не подключено».
public struct LocalOnlySync: SyncService {
    public init() {}
    public var isAvailable: Bool { false }
    public func push(_ data: AppData) async throws { throw SyncError.notConfigured }
    public func pull() async throws -> AppData? { nil }
}
