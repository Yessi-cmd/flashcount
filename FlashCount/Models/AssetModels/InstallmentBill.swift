import Foundation
import SwiftData

@Model
final class InstallmentBill {
    var id: UUID
    var name: String
    var totalAmount: Decimal
    var installmentCount: Int
    var paidInstallments: Int
    var repaymentDay: Int
    var firstRepaymentDate: Date
    var note: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    var normalizedInstallmentCount: Int {
        max(installmentCount, 1)
    }

    var normalizedPaidInstallments: Int {
        min(max(paidInstallments, 0), normalizedInstallmentCount)
    }

    var installmentAmount: Decimal {
        totalAmount / Decimal(normalizedInstallmentCount)
    }

    var paidAmount: Decimal {
        min(installmentAmount * Decimal(normalizedPaidInstallments), totalAmount)
    }

    var remainingInstallments: Int {
        max(normalizedInstallmentCount - normalizedPaidInstallments, 0)
    }

    var remainingAmount: Decimal {
        max(totalAmount - paidAmount, 0)
    }

    var progress: Double {
        guard totalAmount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: paidAmount / totalAmount).doubleValue)
    }

    var isCompleted: Bool {
        remainingInstallments == 0 || remainingAmount <= 0
    }

    init(
        name: String,
        totalAmount: Decimal,
        installmentCount: Int,
        paidInstallments: Int = 0,
        repaymentDay: Int,
        firstRepaymentDate: Date,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.totalAmount = totalAmount
        self.installmentCount = max(installmentCount, 1)
        self.paidInstallments = min(max(paidInstallments, 0), max(installmentCount, 1))
        self.repaymentDay = min(max(repaymentDay, 1), 31)
        self.firstRepaymentDate = firstRepaymentDate
        self.note = note
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func repaymentDate(forInstallment index: Int, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: firstRepaymentDate)
        let firstMonth = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)) ?? firstRepaymentDate
        let targetMonth = calendar.date(byAdding: .month, value: max(index, 0), to: firstMonth) ?? firstMonth
        let dayRange = calendar.range(of: .day, in: .month, for: targetMonth)
        let clampedDay = min(max(repaymentDay, 1), dayRange?.count ?? repaymentDay)
        var targetComponents = calendar.dateComponents([.year, .month], from: targetMonth)
        targetComponents.day = clampedDay
        return calendar.startOfDay(for: calendar.date(from: targetComponents) ?? targetMonth)
    }

    func nextRepaymentDate(from date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard !isArchived, !isCompleted else { return nil }
        return repaymentDate(forInstallment: normalizedPaidInstallments, calendar: calendar)
    }
}
