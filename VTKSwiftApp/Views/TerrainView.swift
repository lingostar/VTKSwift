import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Solar Position Calculator

/// Simplified NOAA solar position algorithm.
/// Computes sun elevation and azimuth from geographic coordinates and time.
struct SolarPosition {
    let elevation: Double   // degrees above horizon (0=horizon, 90=zenith)
    let azimuth: Double     // degrees from north (0=N, 90=E, 180=S, 270=W)

    /// Calculate solar position.
    /// - Parameters:
    ///   - latitude: Observer latitude in degrees (positive north)
    ///   - longitude: Observer longitude in degrees (positive east)
    ///   - dayOfYear: Day of year (1-365)
    ///   - hourLocal: Local time in hours (0.0-24.0)
    ///   - utcOffset: Hours ahead of UTC (e.g. 9 for KST)
    static func calculate(
        latitude: Double,
        longitude: Double,
        dayOfYear: Int,
        hourLocal: Double,
        utcOffset: Double = 9.0  // KST
    ) -> SolarPosition {
        let latRad = latitude * .pi / 180.0
        let doy = Double(dayOfYear)

        // Solar declination (Spencer, 1971)
        let gamma = 2.0 * .pi * (doy - 1.0) / 365.0
        let declination = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2.0 * gamma)
            + 0.000907 * sin(2.0 * gamma)
            - 0.002697 * cos(3.0 * gamma)
            + 0.00148  * sin(3.0 * gamma)

        // Equation of Time (minutes)
        let eqTime = 229.18 * (
            0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2.0 * gamma)
            - 0.04089  * sin(2.0 * gamma)
        )

        // True solar time (minutes)
        let timeOffset = eqTime + 4.0 * longitude - 60.0 * utcOffset
        let trueSolarTime = hourLocal * 60.0 + timeOffset

        // Hour angle (degrees)
        let hourAngle = (trueSolarTime / 4.0) - 180.0
        let haRad = hourAngle * .pi / 180.0

        // Solar zenith angle
        let cosZenith = sin(latRad) * sin(declination)
            + cos(latRad) * cos(declination) * cos(haRad)
        let zenithRad = acos(max(-1.0, min(1.0, cosZenith)))
        let elevationDeg = 90.0 - zenithRad * 180.0 / .pi

        // Solar azimuth
        let sinZenith = sin(zenithRad)
        var cosAzimuth: Double
        if abs(sinZenith) < 0.001 {
            cosAzimuth = 1.0  // Sun at zenith, azimuth undefined
        } else {
            cosAzimuth = (sin(latRad) * cosZenith - sin(declination))
                / (cos(latRad) * sinZenith)
            cosAzimuth = max(-1.0, min(1.0, cosAzimuth))
        }

        var azimuthDeg = acos(cosAzimuth) * 180.0 / .pi
        // Afternoon: azimuth > 180°
        if hourAngle > 0 {
            azimuthDeg = 360.0 - azimuthDeg
        }

        return SolarPosition(
            elevation: max(0, elevationDeg),
            azimuth: azimuthDeg
        )
    }
}

// MARK: - Terrain Color Scheme Model

enum TerrainColorScheme: Int, CaseIterable, Identifiable {
    case elevation = 0
    case satellite = 1
    case grayscale = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .elevation: return "Elevation"
        case .satellite:  return "Natural"
        case .grayscale:  return "Shadow"
        }
    }

    var icon: String {
        switch self {
        case .elevation: return "paintpalette"
        case .satellite:  return "leaf"
        case .grayscale:  return "circle.lefthalf.filled"
        }
    }

    var vtkScheme: VTKTerrainColorScheme {
        VTKTerrainColorScheme(rawValue: rawValue) ?? .elevation
    }
}

// MARK: - Terrain View State

/// Persists terrain rendering state across NavigationSplitView re-navigation.
final class TerrainViewState: ObservableObject {
    @Published var bridge: VTKBridge?
    @Published var isLoaded = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Solar simulation
    @Published var timeOfDay: Double = 10.0      // 0–24 hours
    @Published var dayOfYear: Int = 172           // June 21 (summer solstice)
    @Published var sunElevationDeg: Double = 45.0
    @Published var sunAzimuthDeg: Double = 180.0

    // Terrain settings
    @Published var elevationExaggeration: Double = 2.0
    @Published var shadowsEnabled: Bool = true
    @Published var colorScheme: TerrainColorScheme = .elevation

    // Pohang coordinates
    static let pohangLat = 36.019
    static let pohangLon = 129.343
    static let kstOffset = 9.0

    func updateSolarPosition() {
        let pos = SolarPosition.calculate(
            latitude: Self.pohangLat,
            longitude: Self.pohangLon,
            dayOfYear: dayOfYear,
            hourLocal: timeOfDay,
            utcOffset: Self.kstOffset
        )
        sunElevationDeg = pos.elevation
        sunAzimuthDeg = pos.azimuth
    }

    /// Format time as HH:MM string
    var timeString: String {
        let h = Int(timeOfDay)
        let m = Int((timeOfDay - Double(h)) * 60)
        return String(format: "%02d:%02d", h, m)
    }

    /// Format day of year as approximate date
    var dateString: String {
        let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        var remaining = dayOfYear
        for (i, days) in monthDays.enumerated() {
            if remaining <= days {
                return "\(monthNames[i]) \(remaining)"
            }
            remaining -= days
        }
        return "Dec 31"
    }
}

// MARK: - Terrain View

struct TerrainView: View {
    @ObservedObject var state: TerrainViewState

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoaded {
                // 3D Terrain rendering view
                TerrainRenderView(state: state)
                    .ignoresSafeArea()

                // Controls panel
                controlsPanel
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            } else if state.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading terrain data...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .navigationTitle("Terrain Viewer")
        .onAppear {
            if !state.isLoaded && !state.isLoading {
                state.updateSolarPosition()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mountain.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Urban Sunlight Simulator")
                .font(.title2)

            Text("Pohang, South Korea (포항)\nSRTM 30m DEM Terrain Visualization")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)

            Button {
                loadTerrain()
            } label: {
                Label("Load Pohang Terrain", systemImage: "mountain.2.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)

            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 8) {
            // Time of day slider
            HStack {
                Image(systemName: "sun.max")
                    .frame(width: 20)
                Text("Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
                Slider(value: $state.timeOfDay, in: 5.0...20.0, step: 0.25)
                    .onChange(of: state.timeOfDay) { _ in
                        state.updateSolarPosition()
                        state.bridge?.setSunElevation(
                            state.sunElevationDeg,
                            azimuth: state.sunAzimuthDeg
                        )
                    }
                Text(state.timeString)
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            // Day of year slider
            HStack {
                Image(systemName: "calendar")
                    .frame(width: 20)
                Text("Date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
                Slider(
                    value: Binding(
                        get: { Double(state.dayOfYear) },
                        set: { state.dayOfYear = Int($0) }
                    ),
                    in: 1...365,
                    step: 1
                )
                .onChange(of: state.dayOfYear) { _ in
                    state.updateSolarPosition()
                    state.bridge?.setSunElevation(
                        state.sunElevationDeg,
                        azimuth: state.sunAzimuthDeg
                    )
                }
                Text(state.dateString)
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            // Elevation exaggeration slider
            HStack {
                Image(systemName: "arrow.up.and.down")
                    .frame(width: 20)
                Text("Exag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
                Slider(
                    value: $state.elevationExaggeration,
                    in: 0.5...10.0,
                    step: 0.5
                )
                .onChange(of: state.elevationExaggeration) { newValue in
                    state.bridge?.setElevationExaggeration(newValue)
                }
                Text(String(format: "%.1fx", state.elevationExaggeration))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            // Color scheme & shadow controls
            HStack(spacing: 12) {
                // Color scheme buttons
                ForEach(TerrainColorScheme.allCases) { scheme in
                    colorSchemeButton(scheme)
                }

                Spacer()

                // Shadow toggle
                Toggle(isOn: $state.shadowsEnabled) {
                    Label("Shadows", systemImage: "shadow")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: state.shadowsEnabled) { newValue in
                    state.bridge?.setShadowsEnabled(newValue)
                }
            }

            // Sun info
            HStack {
                Spacer()
                Text(String(format: "Sun: El %.0f° Az %.0f°",
                            state.sunElevationDeg,
                            state.sunAzimuthDeg))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func colorSchemeButton(_ scheme: TerrainColorScheme) -> some View {
        Button {
            state.colorScheme = scheme
            state.bridge?.apply(scheme.vtkScheme)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: scheme.icon)
                    .font(.caption)
                Text(scheme.title)
                    .font(.caption2)
            }
            .frame(width: 56, height: 36)
            .background(
                state.colorScheme == scheme
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        state.colorScheme == scheme
                            ? Color.accentColor
                            : Color.gray.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load Terrain

    private func loadTerrain() {
        state.isLoading = true
        state.errorMessage = nil
        state.updateSolarPosition()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            state.isLoaded = true
            state.isLoading = false
        }
    }
}

// MARK: - Terrain Render View (Platform-specific)

#if os(iOS)
private struct TerrainRenderView: UIViewRepresentable {
    @ObservedObject var state: TerrainViewState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> UIView {
        let bridge = VTKBridge(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        context.coordinator.bridge = bridge

        // Load terrain data
        loadTerrainData(bridge: bridge)

        let view = bridge.renderView

        // Deferred state sync
        let exag = state.elevationExaggeration
        let sunEl = state.sunElevationDeg
        let sunAz = state.sunAzimuthDeg
        let shadows = state.shadowsEnabled
        let scheme = state.colorScheme.vtkScheme

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.state.bridge = bridge
            bridge.setElevationExaggeration(exag)
            bridge.setSunElevation(sunEl, azimuth: sunAz)
            bridge.setShadowsEnabled(shadows)
            bridge.apply(scheme)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let bridge = context.coordinator.bridge else { return }
        let size = uiView.bounds.size
        if size.width > 0 && size.height > 0 {
            bridge.resize(to: size)
        }
    }

    private func loadTerrainData(bridge: VTKBridge) {
        // Try bundled Pohang DEM first
        if let rawURL = Bundle.main.url(
            forResource: "pohang_dem", withExtension: "raw")
        {
            if let metaURL = Bundle.main.url(
                forResource: "pohang_dem_meta", withExtension: "json"),
               let metaData = try? Data(contentsOf: metaURL),
               let meta = try? JSONSerialization.jsonObject(
                with: metaData) as? [String: Any],
               let width = meta["width"] as? Int,
               let height = meta["height"] as? Int,
               let spacing = meta["spacing_meters"] as? [String: Any],
               let sx = spacing["x"] as? Double,
               let sy = spacing["y"] as? Double
            {
                _ = bridge.loadTerrain(
                    fromRawDEM: rawURL.path,
                    width: width,
                    height: height,
                    spacingX: sx,
                    spacingY: sy
                )
                return
            }
            // Fallback: use default metadata for Pohang
            _ = bridge.loadTerrain(
                fromRawDEM: rawURL.path,
                width: 512,
                height: 512,
                spacingX: 24.97,
                spacingY: 30.87
            )
            return
        }

        // No DEM file — load synthetic terrain
        _ = bridge.loadSyntheticTerrain(256)
    }

    class Coordinator {
        var bridge: VTKBridge?
        let state: TerrainViewState
        init(state: TerrainViewState) { self.state = state }
    }
}

#elseif os(macOS)
private struct TerrainRenderView: NSViewRepresentable {
    @ObservedObject var state: TerrainViewState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> NSView {
        let bridge = VTKBridge(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        context.coordinator.bridge = bridge

        // Load terrain data
        loadTerrainData(bridge: bridge)

        let view = bridge.renderView

        // Deferred state sync
        let exag = state.elevationExaggeration
        let sunEl = state.sunElevationDeg
        let sunAz = state.sunAzimuthDeg
        let shadows = state.shadowsEnabled
        let scheme = state.colorScheme.vtkScheme

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.state.bridge = bridge
            bridge.setElevationExaggeration(exag)
            bridge.setSunElevation(sunEl, azimuth: sunAz)
            bridge.setShadowsEnabled(shadows)
            bridge.apply(scheme)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let bridge = context.coordinator.bridge else { return }
        let size = nsView.bounds.size
        if size.width > 0 && size.height > 0 {
            bridge.resize(to: size)
        }
    }

    private func loadTerrainData(bridge: VTKBridge) {
        // Try bundled Pohang DEM first
        if let rawURL = Bundle.main.url(
            forResource: "pohang_dem", withExtension: "raw")
        {
            if let metaURL = Bundle.main.url(
                forResource: "pohang_dem_meta", withExtension: "json"),
               let metaData = try? Data(contentsOf: metaURL),
               let meta = try? JSONSerialization.jsonObject(
                with: metaData) as? [String: Any],
               let width = meta["width"] as? Int,
               let height = meta["height"] as? Int,
               let spacing = meta["spacing_meters"] as? [String: Any],
               let sx = spacing["x"] as? Double,
               let sy = spacing["y"] as? Double
            {
                _ = bridge.loadTerrain(
                    fromRawDEM: rawURL.path,
                    width: width,
                    height: height,
                    spacingX: sx,
                    spacingY: sy
                )
                return
            }
            // Fallback: use default metadata for Pohang
            _ = bridge.loadTerrain(
                fromRawDEM: rawURL.path,
                width: 512,
                height: 512,
                spacingX: 24.97,
                spacingY: 30.87
            )
            return
        }

        // No DEM file — load synthetic terrain
        _ = bridge.loadSyntheticTerrain(256)
    }

    class Coordinator {
        var bridge: VTKBridge?
        let state: TerrainViewState
        init(state: TerrainViewState) { self.state = state }
    }
}
#endif
