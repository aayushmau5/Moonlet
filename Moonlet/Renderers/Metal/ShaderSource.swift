import Foundation

struct ShaderUniforms {
    var time: Float
    var resolution: SIMD2<Float>
}

struct ShaderError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

enum ShaderSource {
    static let vertexFunctionName = "moonlet_vertex"
    static let fragmentFunctionName = "wallpaper"

    static let header = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float time;
        float2 resolution;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut moonlet_vertex(uint vertexID [[vertex_id]]) {
        const float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VertexOut out;
        out.position = float4(corners[vertexID], 0.0, 1.0);
        out.uv = corners[vertexID] * 0.5 + 0.5;
        return out;
    }

    """

    static func combined(_ source: String, fileName: String) -> String {
        header + "#line 1 \"\(fileName)\"\n" + source
    }

    static func describeCompileLog(_ log: String) -> String {
        let pattern = /^.*?:(\d+):\d+: (?:fatal )?error: (.*)$/
        let errors = log.split(separator: "\n").compactMap { line -> String? in
            guard let match = String(line).firstMatch(of: pattern) else { return nil }
            return "line \(match.1): \(match.2)"
        }
        if errors.isEmpty {
            return log.split(separator: "\n").first.map(String.init) ?? log
        }
        return errors.joined(separator: "; ")
    }
}
