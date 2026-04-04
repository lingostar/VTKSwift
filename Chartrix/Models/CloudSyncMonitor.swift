import Foundation
import Combine
import CloudKit

/// CloudKit + iCloud Documents 동기화 상태를 모니터링
/// 앱 최초 실행 시 동기화 진행 중임을 UI에 알려줍니다.
@MainActor
final class CloudSyncMonitor: ObservableObject {

    /// 현재 동기화가 진행 중인지
    @Published var isSyncing: Bool = false

    /// iCloud 계정 상태
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine

    private var syncTimer: Timer?
    private var startTime: Date?
    private var initialChartCount: Int = 0

    /// 최대 동기화 대기 시간 (초) — 이후에는 자동으로 완료 처리
    private let maxSyncDuration: TimeInterval = 15

    init() {
        checkInitialSyncState()
    }

    // MARK: - Initial Sync Detection

    private func checkInitialSyncState() {
        // iCloud 사용 불가하면 동기화 표시 불필요
        guard ChartStorage.isICloudAvailable else {
            isSyncing = false
            return
        }

        // iCloud 계정 상태 확인
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

        // SwiftData @Query가 자동으로 업데이트하므로,
        // 뷰가 차트 목록을 감지하면 배너만 보여주고
        // 시간이 지나면 자연스럽게 사라짐
    }

    private func finishSync() {
        isSyncing = false
        syncTimer?.invalidate()
        syncTimer = nil
        startTime = nil
    }

    /// 외부에서 데이터가 로드되었음을 알릴 때 (목록에 차트가 나타남)
    func notifyDataLoaded() {
        // 데이터가 도착하면 약간의 지연 후 동기화 완료 처리
        // (추가 데이터가 더 올 수 있으므로 바로 끄지 않음)
        guard isSyncing else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            finishSync()
        }
    }
}
