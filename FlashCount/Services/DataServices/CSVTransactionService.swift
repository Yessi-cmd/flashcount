import Foundation
import SwiftData

/// Portable transaction-only CSV exchange for spreadsheet workflows.
@MainActor
final class CSVTransactionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) { self.modelContext = modelContext }

    struct SkippedRow: Equatable {
        let rowNumber: Int
        let reason: String
    }

    struct ImportResult: Equatable {
        var imported = 0
        var skippedRows: [SkippedRow] = []

        var skipped: Int { skippedRows.count }

        var summary: String {
            guard skipped > 0 else { return "已导入 \(imported) 笔账单" }
            let details = skippedRows.prefix(3)
                .map { "第 \($0.rowNumber) 行：\($0.reason)" }
                .joined(separator: "；")
            let remaining = skipped > 3 ? "等 \(skipped) 行" : ""
            return "已导入 \(imported) 笔账单，跳过 \(skipped) 行\(details.isEmpty ? "" : "（\(details)\(remaining.isEmpty ? "" : "；\(remaining)")）")"
        }
    }

    enum ImportError: LocalizedError {
        case invalidHeader
        case malformedCSV

        var errorDescription: String? {
            switch self {
            case .invalidHeader: return "CSV 表头必须为 id、date、type、amount、category、note（dailyBudget 可选）"
            case .malformedCSV: return "CSV 中存在未闭合的引号"
            }
        }
    }

    func exportToFile() throws -> URL {
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)]))
        let formatter = ISO8601DateFormatter()
        var rows = ["id,date,type,amount,category,note,dailyBudget"]
        for item in transactions {
            rows.append([
                item.id.uuidString, formatter.string(from: item.date), item.isExpense ? "expense" : "income",
                NSDecimalNumber(decimal: item.amount).stringValue, item.category?.name ?? "", item.note,
                item.dailyBudgetOverride.map { $0 ? "include" : "exclude" } ?? "inherit"
            ].map(csvEscape).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FlashCount_Transactions.csv")
        guard let data = rows.joined(separator: "\n").data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    func importCSV(from url: URL) throws -> ImportResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = try parseCSVRecords(content)
        guard let header = rows.first else { throw ImportError.invalidHeader }
        var headerValues = header.values
        if let first = headerValues.first {
            headerValues[0] = first.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        }
        guard headerValues.count >= 6,
              Array(headerValues.prefix(6)) == ["id", "date", "type", "amount", "category", "note"],
              headerValues.count == 6 || headerValues[6] == "dailyBudget" else {
            throw ImportError.invalidHeader
        }
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>())
        var defaultLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first

        var seenIDs = Set(try modelContext.fetch(FetchDescriptor<Transaction>()).map(\.id))
        let formatter = ISO8601DateFormatter()
        var result = ImportResult()
        var importedCashDelta: Decimal = 0
        for row in rows.dropFirst() {
            let values = row.values
            guard values.count >= 6 else {
                result.skippedRows.append(.init(rowNumber: row.number, reason: "列数不足"))
                continue
            }
            guard let id = UUID(uuidString: values[0]) else {
                result.skippedRows.append(.init(rowNumber: row.number, reason: "ID 不是有效 UUID"))
                continue
            }
            guard !seenIDs.contains(id) else {
                result.skippedRows.append(.init(rowNumber: row.number, reason: "ID 已存在或在文件中重复"))
                continue
            }
            guard let date = formatter.date(from: values[1]) else {
                result.skippedRows.append(.init(rowNumber: row.number, reason: "日期不是 ISO 8601 格式"))
                continue
            }
            guard let amount = Decimal(string: values[3]), amount > 0 else {
                result.skippedRows.append(.init(rowNumber: row.number, reason: "金额必须大于零"))
                continue
            }
            guard values[2] == "expense" || values[2] == "income" else {
                result.skippedRows.append(.init(rowNumber: row.number, reason: "type 必须为 expense 或 income"))
                continue
            }
            let isExpense = values[2] == "expense"
            let category = categories.first { $0.name == values[4] && $0.isExpense == isExpense }
            let cashDelta = isExpense ? -amount : amount
            if defaultLedger == nil {
                let created = Ledger.defaultLedgers()[0]
                modelContext.insert(created)
                defaultLedger = created
            }
            let transaction = Transaction(
                amount: amount,
                isExpense: isExpense,
                note: values[5],
                date: date,
                cashPoolDelta: cashDelta,
                dailyBudgetOverride: values.count > 6 ? dailyBudgetOverride(from: values[6]) : nil,
                category: category,
                ledger: defaultLedger
            )
            transaction.id = id
            modelContext.insert(transaction)
            seenIDs.insert(id)
            importedCashDelta += cashDelta
            result.imported += 1
        }

        do {
            try CashPoolService(modelContext: modelContext).applyImportedTransactionDeltas(importedCashDelta)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return result
    }

    private func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func dailyBudgetOverride(from value: String) -> Bool? {
        switch value.lowercased() {
        case "include", "true", "1", "yes": return true
        case "exclude", "false", "0", "no": return false
        default: return nil
        }
    }

    private struct CSVRecord {
        let number: Int
        let values: [String]
    }

    /// Parses RFC 4180-style records before validating their columns, so a
    /// note can contain commas, escaped quotes, and physical line breaks.
    private func parseCSVRecords(_ content: String) throws -> [CSVRecord] {
        var records: [CSVRecord] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var rowNumber = 1
        var index = content.startIndex

        func finishRecord() {
            fields.append(field)
            records.append(CSVRecord(number: rowNumber, values: fields))
            fields.removeAll(keepingCapacity: true)
            field.removeAll(keepingCapacity: true)
            rowNumber += 1
        }

        while index < content.endIndex {
            let character = content[index]
            if character == "\"" {
                let next = content.index(after: index)
                if quoted, next < content.endIndex, content[next] == "\"" {
                    field.append(character)
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                fields.append(field)
                field.removeAll(keepingCapacity: true)
            } else if (character == "\n" || character == "\r"), !quoted {
                if character == "\r" {
                    let next = content.index(after: index)
                    if next < content.endIndex, content[next] == "\n" { index = next }
                }
                finishRecord()
            } else {
                field.append(character)
            }
            index = content.index(after: index)
        }

        guard !quoted else { throw ImportError.malformedCSV }
        if !fields.isEmpty || !field.isEmpty {
            finishRecord()
        }
        return records
    }
}
