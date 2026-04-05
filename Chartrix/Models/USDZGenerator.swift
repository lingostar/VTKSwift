import Foundation
import SceneKit

/// Convert DICOM mesh data to USDZ file
enum USDZGenerator {

    /// Generate USDZ from mesh data extracted by VTKBridge
    static func create(
        vertices: Data, normals: Data, faces: Data,
        color: SIMD3<Float>, roughness: Float,
        name: String, outputURL: URL
    ) -> Bool {
        print("[USDZ] Starting generation: \(name)")
        print("[USDZ] vertices=\(vertices.count) bytes, normals=\(normals.count) bytes, faces=\(faces.count) bytes")
        print("[USDZ] Output: \(outputURL.path)")

        let vertexCount = vertices.count / (3 * MemoryLayout<Float>.size)
        let faceCount = faces.count / (3 * MemoryLayout<UInt32>.size)
        print("[USDZ] vertexCount=\(vertexCount), faceCount=\(faceCount)")
        guard vertexCount > 0, faceCount > 0 else {
            print("[USDZ] ERROR: Empty mesh data")
            return false
        }

        // SCNGeometrySource — positions
        let positionSource = SCNGeometrySource(
            data: vertices,
            semantic: .vertex,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 3 * MemoryLayout<Float>.size
        )

        // SCNGeometrySource — normals
        let normalSource = SCNGeometrySource(
            data: normals,
            semantic: .normal,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 3 * MemoryLayout<Float>.size
        )

        // SCNGeometryElement — triangle indices
        let element = SCNGeometryElement(
            data: faces,
            primitiveType: .triangles,
            primitiveCount: faceCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [positionSource, normalSource], elements: [element])

        // PBR Material
        let material = SCNMaterial()
        material.name = name
        material.lightingModel = .physicallyBased
        material.diffuse.contents = platformColor(r: color.x, g: color.y, b: color.z)
        material.roughness.contents = NSNumber(value: roughness)
        material.metalness.contents = NSNumber(value: 0.0)
        material.isDoubleSided = true
        geometry.materials = [material]

        // Compose scene
        let node = SCNNode(geometry: geometry)
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)

        // Export USDZ
        print("[USDZ] Writing SCNScene to USDZ ...")
        let delegate: SCNSceneExportDelegate? = nil
        let success = scene.write(to: outputURL, options: nil, delegate: delegate, progressHandler: nil)

        if success {
            let fm = FileManager.default
            if fm.fileExists(atPath: outputURL.path) {
                let attrs = try? fm.attributesOfItem(atPath: outputURL.path)
                let size = attrs?[.size] as? Int64 ?? 0
                print("[USDZ] Export succeeded: \(size) bytes")
            }
        } else {
            print("[USDZ] SCNScene.write failed")
        }
        return success
    }

    /// Create platform-specific color
    private static func platformColor(r: Float, g: Float, b: Float) -> Any {
        #if os(iOS)
        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
        #else
        return NSColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
        #endif
    }
}
