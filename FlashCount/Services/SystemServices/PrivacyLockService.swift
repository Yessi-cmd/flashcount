import Combine
import Foundation
import LocalAuthentication
import SwiftUI

enum PrivacyVisibilityPolicy {
    static func hidesIncome(isExpense: Bool, isUnlocked: Bool) -> Bool {
        !isExpense && !isUnlocked
    }

    static func hidesProtectedMetadata(isProtectedIncome: Bool, isUnlocked: Bool) -> Bool {
        isProtectedIncome && !isUnlocked
    }

    static func hidesAssets(isUnlocked: Bool) -> Bool {
        !isUnlocked
    }
}

@MainActor
final class PrivacyLockService: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var lastError: String?
    @Published var isRevealConfirmationPresented = false

    var maskedText: String { "****" }
    var hidesSensitiveAmounts: Bool { !isUnlocked }

    func requestReveal() {
        guard !isUnlocked else { return }
        lastError = nil
        isRevealConfirmationPresented = true
    }

    func confirmReveal() async -> Bool {
        isRevealConfirmationPresented = false
        return await unlock()
    }

    private func unlock() async -> Bool {
        lastError = nil
        let reason = "显示收入、资产和其他隐私金额"

        switch await evaluateBiometrics(reason: reason) {
        case .unlocked:
            return true
        case .cancelled:
            return false
        case .needsFallback:
            return await evaluateDeviceAuthentication(reason: reason)
        }
    }

    private enum AuthenticationAttempt {
        case unlocked
        case cancelled
        case needsFallback
    }

    private func evaluateBiometrics(reason: String) async -> AuthenticationAttempt {
        let context = LAContext()
        context.localizedFallbackTitle = "输入设备密码"
        context.localizedCancelTitle = "取消"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .needsFallback
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            isUnlocked = success
            return success ? .unlocked : .needsFallback
        } catch let authError as LAError {
            if authError.code == .userCancel || authError.code == .systemCancel || authError.code == .appCancel {
                lastError = nil
                isUnlocked = false
                return .cancelled
            }
            return .needsFallback
        } catch {
            return .needsFallback
        }
    }

    private func evaluateDeviceAuthentication(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = error?.localizedDescription ?? "当前设备无法验证身份"
            return false
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isUnlocked = success
            return success
        } catch let authError as LAError {
            if authError.code == .userCancel || authError.code == .systemCancel || authError.code == .appCancel {
                lastError = nil
            } else {
                lastError = authError.localizedDescription
            }
            isUnlocked = false
            return false
        } catch {
            lastError = error.localizedDescription
            isUnlocked = false
            return false
        }
    }

    func lock() {
        isRevealConfirmationPresented = false
        isUnlocked = false
    }
}

struct PrivacyVisibilityButton: View {
    @EnvironmentObject private var privacyLock: PrivacyLockService

    var body: some View {
        Button {
            if privacyLock.isUnlocked {
                privacyLock.lock()
                HapticManager.selection()
            } else {
                privacyLock.requestReveal()
            }
        } label: {
            Image(systemName: privacyLock.isUnlocked ? "eye.fill" : "eye.slash.fill")
                .foregroundStyle(privacyLock.isUnlocked ? DesignSystem.primaryColor : DesignSystem.textSecondary)
        }
        .accessibilityLabel(privacyLock.isUnlocked ? "隐藏隐私金额" : "验证并显示隐私金额")
        .accessibilityHint(privacyLock.isUnlocked ? "立即隐藏所有收入和资产金额" : "先确认，再验证设备所有者身份")
    }
}
