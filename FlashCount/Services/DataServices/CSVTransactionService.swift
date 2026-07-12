import Foundation
import SwiftData

/// Portable transaction-only CSV exchange for spreadsheet workflows.
@MainActor
final class CSVTransactionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) { self.modelContext = modelContext }

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

    func importCSV(from url: URL) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = content.split(whereSeparator: \.isNewline).dropFirst()
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>())
        var defaultLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first

        var seenIDs = Set(try modelContext.fetch(FetchDescriptor<Transaction>()).map(\.id.uuidString))
        let formatter = ISO8601DateFormatter()
        var imported = 0
        var importedCashDelta: Decimal = 0
        for row in rows {
            let values = parseCSV(String(row))
            guard values.count >= 6,
                  !seenIDs.contains(values[0]),
                  let id = UUID(uuidString: values[0]),
                  let date = formatter.date(from: values[1]),
                  let amount = Decimal(string: values[3]),
                  amount > 0,
                  values[2] == "expense" || values[2] == "income" else {
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
            seenIDs.insert(values[0])
            importedCashDelta += cashDelta
            imported += 1
        }

        CashPoolService(modelContext: modelContext).applyImportedTransactionDeltas(importedCashDelta)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return imported
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

    private func parseCSV(_ row: String) -> [String] {
        var result: [String] = []; var value = ""; var quoted = false; var index = row.startIndex
        while index < row.endIndex {
            let char = row[index]
            if char == "\"" {
                let next = row.index(after: index)
                if quoted, next < row.endIndex, row[next] == "\"" { value.append(char); index = next }
                else { quoted.toggle() }
            } else if char == ",", !quoted { result.append(value); value = "" }
            else { value.append(char) }
            index = row.index(after: index)
        }
        result.append(value); return result
    }
}
