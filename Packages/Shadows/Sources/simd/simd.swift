// Apple's `simd` module for wasm: the vector types are the standard library's (`SIMD3<Float>`),
// and these are the C functions over them that apps call (`simd_normalize`, `simd_cross`,
// `simd_dot`, `simd_length`, `simd_mix`, `simd_clamp`), with the `simd_float3` style names.
#if os(WASI)
@_exported import WASILibc

public typealias simd_float2 = SIMD2<Float>
public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>
public typealias simd_double2 = SIMD2<Double>
public typealias simd_double3 = SIMD3<Double>
public typealias simd_double4 = SIMD4<Double>
public typealias simd_int2 = SIMD2<Int32>
public typealias simd_int3 = SIMD3<Int32>
public typealias simd_int4 = SIMD4<Int32>
public typealias simd_uint2 = SIMD2<UInt32>
public typealias simd_uint3 = SIMD3<UInt32>
public typealias simd_uint4 = SIMD4<UInt32>

public func simd_dot<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: FloatingPoint { (x * y).sum() }
public func simd_length_squared<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: FloatingPoint { (x * x).sum() }
public func simd_length<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: FloatingPoint { (x * x).sum().squareRoot() }
public func simd_distance<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_length(x - y) }
public func simd_distance_squared<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_length_squared(x - y) }
public func simd_normalize<V: SIMD>(_ x: V) -> V where V.Scalar: FloatingPoint { x / simd_length(x) }
public func simd_mix<V: SIMD>(_ x: V, _ y: V, _ t: V) -> V where V.Scalar: FloatingPoint { x + (y - x) * t }
public func simd_clamp<V: SIMD>(_ x: V, _ lo: V, _ hi: V) -> V where V.Scalar: FloatingPoint { x.clamped(lowerBound: lo, upperBound: hi) }
public func simd_abs<V: SIMD>(_ x: V) -> V where V.Scalar: FloatingPoint { V(x.indices.map { abs(x[$0]) }) }
public func simd_min<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: Comparable { pointwiseMin(x, y) }
public func simd_max<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: Comparable { pointwiseMax(x, y) }
public func simd_cross<S: FloatingPoint & SIMDScalar>(_ x: SIMD3<S>, _ y: SIMD3<S>) -> SIMD3<S> {
    SIMD3(x.y * y.z - x.z * y.y, x.z * y.x - x.x * y.z, x.x * y.y - x.y * y.x)
}
public func simd_reflect<V: SIMD>(_ x: V, _ n: V) -> V where V.Scalar: FloatingPoint { x - 2 * simd_dot(x, n) * n }

public func normalize<V: SIMD>(_ x: V) -> V where V.Scalar: FloatingPoint { simd_normalize(x) }
public func cross<S: FloatingPoint & SIMDScalar>(_ x: SIMD3<S>, _ y: SIMD3<S>) -> SIMD3<S> { simd_cross(x, y) }
public func dot<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_dot(x, y) }
public func length<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_length(x) }
public func distance<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_distance(x, y) }
public func mix<V: SIMD>(_ x: V, _ y: V, t: V.Scalar) -> V where V.Scalar: FloatingPoint { x + (y - x) * t }
#endif
