import Foundation
import SceneKit

/// DICOM 메쉬 데이터를 USDZ 파일로 변환
enum USDZGenerator {

    /// VTKBridge에서 추출한 메쉬 데이터로 USDZ 생성
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

        // Scene 구성
        let node = SCNNode(geometry: geometry)
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)

        // USDZ 내보내기
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

    /// 플랫폼별 색상 생성
    private static func platformColor(r: Float, g: Float, b: Float) -> Any {
        #if os(iOS)
        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
        #else
        return NSColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
        #endif
    }
}
