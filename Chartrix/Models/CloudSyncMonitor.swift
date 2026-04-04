import Foundation
import Combine
import CloudKit

/// CloudKit + iCloud Documents 동기화 상태를 모니터링
/// 앱 최초 실행 시 동기화 진행 중임을 UI에 알려줍니다.
/// iCloud 로그아웃 감지도 담당합니다.
@MainActor
final class CloudSyncMonitor: ObservableObject {

    /// 현재 동기화가 진행 중인지
    @Published var isSyncing: Bool = false

    /// iCloud에서 로그아웃되어 데이터 접근 불가 상태
    @Published var isSignedOutFromICloud: Bool = false

    /// iCloud 계정 상태
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine

    private var syncTimer: Timer?
    private var startTime: Date?
    private var initialChartCount: Int = 0

    /// 최대 동기화 대기 시간 (초) — 이후에는 자동으로 완료 처리
    private let maxSyncDuration: TimeInterval = 15

    init() {
        checkInitialState()
    }

    // MARK: - Initial State Detection

    private func checkInitialState() {
        // 1) iCloud 로그아웃 감지
        if ChartStorage.needsICloudReSignIn {
            isSignedOutFromICloud = true
            isSyncing = false
            return
        }

        // 2) iCloud 사용 가능 여부 기록
        ChartStorage.recordICloudUsage()

        // 3) iCloud 사용 불가하면 동기화 표시 불필요
        guard ChartStorage.isICloudAvailable else {
            isSyncing = false
            return
        }

        // 4) iCloud 계정 상태 확인
        CKContainer(identifier: "iCloud.codershigh.Chartrix").accountStatus { [weak self] status, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accountStatus = status

                if status == .available {
                    // iCloud 로그인 상태 → 동기화 시작 표시
                    self.beginSyncWatch()
                } else {
                    self.isSyncing = false
                }
            }
        }

        // 5) iCloud 계정 변경 알림 구독
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAccountChange()
            }
        }
    }

    /// iCloud 계정 변경 처리 (로그인/로그아웃)
    private func handleAccountChange() {
        ChartStorage.recordICloudUsage()

        if ChartStorage.isICloudAvailable {
            // 다시 로그인됨
            isSignedOutFromICloud = false
        } else if ChartStorage.wasUsingICloud {
            // 로그아웃됨
            isSignedOutFromICloud = true
            finishSync()
        }
    }

    /// 동기화 모니터링 시작 — 첫 데이터 도착 또는 타임아웃까지
    private func beginSyncWatch() {
        isSyncing = true
        startTime = Date()

        // 주기적으로 동기화 상태 체크 (2초마다)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateSyncState()
            }
        }
    }

    private func evaluateSyncState() {
        guard let startTime else {
            finishSync()
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // 타임아웃: 동기화 대기 종료
        if elapsed >= maxSyncDuration {
            finishSync()
            return
        }
    }

    private func finishSync() {
        isSyncing = false
        syncTimer?.invalidate()
        syncTimer = nil
        startTime = nil
    }

    /// 외부에서 데이터가 로드되었음을 알릴 때 (목록에 차트가 나타남)
    func notifyDataLoaded() {
        guard isSyncing else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            finishSync()
        }
    }
}
