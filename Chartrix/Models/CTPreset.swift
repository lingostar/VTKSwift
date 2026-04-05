import Foundation

/// CT volume rendering preset
enum CTPreset: Int, CaseIterable, Identifiable {
    case softTissue = 0
    case bone = 1
    case lung = 2
    case brain = 3
    case abdomen = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .softTissue: return "Soft Tissue"
        case .bone:       return "Bone"
        case .lung:       return "Lung"
        case .brain:      return "Brain"
        case .abdomen:    return "Abdomen"
        }
    }

    var icon: String {
        switch self {
        case .softTissue: return "figure.stand"
        case .bone:       return "figure.walk"
        case .lung:       return "lungs"
        case .brain:      return "brain.head.profile"
        case .abdomen:    return "cross.vial"
        }
    }

    var vtkPreset: VTKVolumePreset {
        VTKVolumePreset(rawValue: rawValue) ?? .softTissue
    }
}
