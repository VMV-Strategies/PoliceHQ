import Foundation
import SQLite3

/// Errors raised by the SQLite wrapper.
public enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case bind(String)

    public var description: String {
        switch self {
        case .open(let m): return "SQLite open failed: \(m)"
        case .prepare(let m): return "SQLite prepare failed: \(m)"
        case .step(let m): return "SQLite step failed: \(m)"
        case .bind(let m): return "SQLite bind failed: \(m)"
        }
    }
}

/// Values that can be bound to statement parameters.
public enum SQLValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case null
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A minimal, synchronous SQLite connection. Not thread-safe; use one per actor/queue.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    public let path: String

    public init(path: String, readOnly: Bool) throws {
        self.path = path
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let db = db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            sqlite3_close(db)
            throw SQLiteError.open(msg)
        }
        handle = db
        if !readOnly {
            try execute("PRAGMA foreign_keys = ON")
        }
    }

    /// Opens a private in-memory database (used by tests and fixtures).
    public static func inMemory() throws -> SQLiteDatabase {
        try SQLiteDatabase(path: ":memory:", readOnly: false)
    }

    deinit {
        if let handle = handle {
            sqlite3_close_v2(handle)
        }
    }

    private var errorMessage: String {
        guard let handle = handle else { return "closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    /// Executes one or more SQL statements without results.
    public func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw SQLiteError.step(msg)
        }
    }

    /// Runs a statement with parameters, discarding rows.
    public func run(_ sql: String, _ params: [SQLValue] = []) throws {
        _ = try query(sql, params, map: { _ in 0 })
    }

    /// Runs a query and maps every row.
    @discardableResult
    public func query<T>(_ sql: String, _ params: [SQLValue] = [], map: (SQLiteRow) throws -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw SQLiteError.prepare("\(errorMessage) — \(sql.prefix(120))")
        }
        defer { sqlite3_finalize(statement) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch p {
            case .text(let s): rc = sqlite3_bind_text(statement, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let v): rc = sqlite3_bind_int64(statement, idx, v)
            case .double(let v): rc = sqlite3_bind_double(statement, idx, v)
            case .null: rc = sqlite3_bind_null(statement, idx)
            }
            if rc != SQLITE_OK { throw SQLiteError.bind(errorMessage) }
        }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                out.append(try map(SQLiteRow(statement: statement)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.step(errorMessage)
            }
        }
        return out
    }
}

/// Accessor for the current row of a statement.
public struct SQLiteRow {
    let statement: OpaquePointer

    public func string(_ i: Int32) -> String? {
        guard sqlite3_column_type(statement, i) != SQLITE_NULL, let c = sqlite3_column_text(statement, i) else { return nil }
        return String(cString: c)
    }

    public func text(_ i: Int32) -> String { string(i) ?? "" }

    public func int(_ i: Int32) -> Int? {
        guard sqlite3_column_type(statement, i) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, i))
    }

    public func bool(_ i: Int32) -> Bool { (int(i) ?? 0) != 0 }
}
