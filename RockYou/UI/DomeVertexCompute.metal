// DomeVertexCompute.metal
// RockYou
//
// Compute shader that generates dome vertices entirely on GPU.
// No CPU vertex generation needed - just dispatch and go!
//
// Output format matches what FragmentGPUShader's geometry modifier expects:
//   - position: float3 (sphere surface position)
//   - normal: float3 (face normal, pointing outward)
//   - uv: float2 (fragmentIndex in x, 0 in y)

#include <metal_stdlib>
using namespace metal;

// Must match Swift's DomeComputeParams
struct DomeComputeParams {
    float radius;
    uint latSegments;
    uint lonSegments;
    uint totalTriangles;    // For bounds checking
};

// Output vertex format - must match LowLevelMesh layout
// IMPORTANT: Use packed_float3 to get exactly 12 bytes (float3 aligns to 16!)
struct DomeVertex {
    packed_float3 position;  // 12 bytes, offset 0
    packed_float3 normal;    // 12 bytes, offset 12
    float2 uv;               // 8 bytes, offset 24
};                           // Total: 32 bytes

// Compute face normal from three vertices (CCW winding)
float3 computeFaceNormal(float3 v0, float3 v1, float3 v2) {
    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    // Ensure normal points outward (same direction as centroid)
    float3 center = (v0 + v1 + v2) / 3.0f;
    if (dot(normal, center) < 0) {
        normal = -normal;
    }
    return normal;
}

// Main compute kernel - one thread per vertex (3 threads per triangle)
kernel void generateDomeVertices(
    device DomeVertex* vertices [[buffer(0)]],
    constant DomeComputeParams& params [[buffer(1)]],
    uint vertexId [[thread_position_in_grid]]
) {
    // Bounds check
    uint totalVertices = params.totalTriangles * 3;
    if (vertexId >= totalVertices) {
        return;
    }

    // Which triangle and which vertex within it?
    uint triangleIndex = vertexId / 3;
    uint vertexInTriangle = vertexId % 3;

    // Tessellation layout (must match Swift and FragmentGPUShader exactly!):
    // - First lonSegments triangles are pole triangles (lat=0)
    // - After that, each lat band has lonSegments * 2 triangles

    int lat, lon, triangleInQuad;
    uint lonSegments = params.lonSegments;
    uint latSegments = params.latSegments;
    float radius = params.radius;

    if (triangleIndex < lonSegments) {
        // Pole triangle
        lat = 0;
        lon = int(triangleIndex);
        triangleInQuad = 0;
    } else {
        uint adjustedIndex = triangleIndex - lonSegments;
        uint trianglesPerBand = lonSegments * 2;
        lat = 1 + int(adjustedIndex / trianglesPerBand);
        uint lonIndex = adjustedIndex % trianglesPerBand;
        lon = int(lonIndex / 2);
        triangleInQuad = int(lonIndex % 2);
    }

    // Compute spherical coordinates
    float theta1 = (float(lat) / float(latSegments)) * (M_PI_F / 2.0f);
    float theta2 = (float(lat + 1) / float(latSegments)) * (M_PI_F / 2.0f);
    float phi1 = (float(lon) / float(lonSegments)) * 2.0f * M_PI_F;
    float phi2 = (float((lon + 1) % int(lonSegments)) / float(lonSegments)) * 2.0f * M_PI_F;
    // Handle wrap-around for last longitude segment
    if (lon == int(lonSegments) - 1) {
        phi2 = 2.0f * M_PI_F;
    }

    float st1 = sin(theta1), ct1 = cos(theta1);
    float st2 = sin(theta2), ct2 = cos(theta2);
    float sp1 = sin(phi1), cp1 = cos(phi1);
    float sp2 = sin(phi2), cp2 = cos(phi2);

    // Four corners of the quad
    float3 p00 = float3(radius * st1 * cp1, radius * ct1, radius * st1 * sp1);
    float3 p10 = float3(radius * st2 * cp1, radius * ct2, radius * st2 * sp1);
    float3 p01 = float3(radius * st1 * cp2, radius * ct1, radius * st1 * sp2);
    float3 p11 = float3(radius * st2 * cp2, radius * ct2, radius * st2 * sp2);

    // Select triangle vertices based on lat and triangleInQuad
    float3 triVerts[3];
    if (lat == 0) {
        // Pole triangle: [p00, p11, p10]
        triVerts[0] = p00;
        triVerts[1] = p11;
        triVerts[2] = p10;
    } else if (triangleInQuad == 0) {
        // Quad triangle 0: [p00, p11, p10]
        triVerts[0] = p00;
        triVerts[1] = p11;
        triVerts[2] = p10;
    } else {
        // Quad triangle 1: [p00, p01, p11]
        triVerts[0] = p00;
        triVerts[1] = p01;
        triVerts[2] = p11;
    }

    // Compute face normal (same for all 3 vertices of this triangle)
    float3 faceNormal = computeFaceNormal(triVerts[0], triVerts[1], triVerts[2]);

    // Write output vertex
    vertices[vertexId].position = triVerts[vertexInTriangle];
    vertices[vertexId].normal = faceNormal;
    vertices[vertexId].uv = float2(float(triangleIndex), 0.0f);  // fragmentIndex in UV.x
}

// Alternative: Generate indices for indexed drawing (more memory efficient)
// One thread per triangle, outputs 3 indices
kernel void generateDomeIndices(
    device uint* indices [[buffer(0)]],
    constant DomeComputeParams& params [[buffer(1)]],
    uint triangleId [[thread_position_in_grid]]
) {
    if (triangleId >= params.totalTriangles) {
        return;
    }

    // Simple sequential indexing - each triangle uses 3 consecutive vertices
    uint baseVertex = triangleId * 3;
    indices[triangleId * 3 + 0] = baseVertex + 0;
    indices[triangleId * 3 + 1] = baseVertex + 1;
    indices[triangleId * 3 + 2] = baseVertex + 2;
}
