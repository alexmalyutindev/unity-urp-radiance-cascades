#include "Common.hlsl"

// -------------------------------------------------------------------------------------
// Soft directional-bin splatting.
//
// Both of the original code's giant 16-step unrolled blocks turn out to be the exact
// same closed-form function, just called with different shape parameters:
//
//   coverage(x) = sign(x - center) * rampSlope *
//                 ( d + (max(0, d - distConst)^2 * -0.5) / invCurve )
//   where d = min(|x - center|, distConst + invCurve)
//
// This is evaluated at x = 0 (baseline) and then at each of the 16 bin edges
// x = 1/16 .. 16/16. The *difference* between consecutive evaluations is the
// "coverage" a bin received, which is turned into a soft falloff factor via
// pow(clamp(1 - coverage*16, 0, 1), sharpness) and used to attenuate/accumulate
// that directional bin's color and remaining transmittance.
//
// This is effectively an anti-aliased, quadratic-B-spline-style splat of a value
// (with some uncertainty half-width) into a 16-bin discretized direction/depth axis.
// -------------------------------------------------------------------------------------
float EvaluateSoftCoverage(float x, float center, float distConst, float invCurve, float rampSlope)
{
    float signMul = (x > center) ? 1.0 : -1.0;
    float d = min(abs(x - center), distConst + invCurve);
    float q = max(0.0, d - distConst);
    return signMul * rampSlope * (d + ((q * q) * -0.5) / invCurve);
}

// Splats `signedColor` into all 16 directional bins of `sector`, softly, according to
// the coverage shape (center/distConst/invCurve/rampSlope) and a falloff sharpness.
// Bin (row, col) = (bin / 4, bin % 4), matching the original code's manual unroll order.
void AccumulateSoftBins(
    inout IntegrationSector sector, float4 signedColor,
    float center, float distConst, float invCurve, float rampSlope,
    float sharpness)
{
    float prevCoverage = EvaluateSoftCoverage(0.0, center, distConst, invCurve, rampSlope);

    [unroll]
    for (int bin = 0; bin < 16; bin++)
    {
        float x = float(bin + 1) / 16.0;
        float coverage = EvaluateSoftCoverage(x, center, distConst, invCurve, rampSlope);
        float falloff = pow(clamp(1.0 - (coverage - prevCoverage) * 16.0, 0.0, 1.0), sharpness);

        int row = bin / 4;
        int col = bin % 4;

        sector.color[row] += (signedColor * sector.transmittance[row][col]) * (1.0 - falloff) * 0.25f;
        sector.transmittance[row][col] *= falloff;

        prevCoverage = coverage;
    }
}
