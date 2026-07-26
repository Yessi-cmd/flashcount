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

    var maskedText: String { "****" }
    var hidesSensitiveAmounts: Bool { !isUnlocked }

    init() {
#if DEBUG
        // 隐私金额默认遮挡，而解锁要过生物识别——UI 测试和视觉走查无法完成。
        // 仅 DEBUG 编译，Release 二进制里不存在这段。
        if ProcessInfo.processInfo.arguments.contains("-uiTestUnlockPrivacy") {
            isUnlocked = true
        }
#endif
    }

    /// 用户点眼睛按钮或点一个被遮挡的数字时直接进生物识别。
    ///
    /// 这里以前先弹一次「显示隐私金额？」确认，再走 Face ID——两步里第一步没有
    /// 提供任何新信息：用户主动点的就是那个数字，意图已经明确，而系统验证弹窗
    /// 本身就是确认环节。原先那句说明并入了下面的验证原因文案。
    func requestReveal() {
        guard !isUnlocked else { return }
        lastError = nil
        Task { _ = await unlock() }
    }

    private func unlock() async -> Bool {
        lastError = nil
        let reason = "显示收入、资产和其他隐私金额；本次使用期间保持可见，进入后台后自动隐藏"

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
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(privacyLock.isUnlocked ? "隐藏隐私金额" : "验证并显示隐私金额")
        .accessibilityHint(privacyLock.isUnlocked ? "立即隐藏所有收入和资产金额" : "验证设备所有者身份后显示，进入后台会自动隐藏")
    }
}
