import Combine
import Foundation
import LocalAuthentication

@MainActor
final class PrivacyLockService: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var lastError: String?

    var maskedText: String { "****" }

    func unlock() async -> Bool {
        let reason = "查看工资、资金池、储蓄目标和分期账单"

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
                lastError = authError.localizedDescription
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
        } catch {
            lastError = error.localizedDescription
            isUnlocked = false
            return false
        }
    }

    func lock() {
        isUnlocked = false
    }
}
