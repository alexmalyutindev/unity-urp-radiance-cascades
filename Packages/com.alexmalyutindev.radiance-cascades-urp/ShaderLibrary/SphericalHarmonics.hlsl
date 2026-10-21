#ifndef SPHERICAL_HARMONICS_INCLUDED
#define SPHERICAL_HARMONICS_INCLUDED

#define kSHBasis0  0.28209479177387814347f // {0, 0} : 1/2 * sqrt(1/Pi)
#define kSHBasis1  0.48860251190291992159f // {1, 0} : 1/2 * sqrt(3/Pi)
#define kSHBasis2  1.09254843059207907054f // {2,-2} : 1/2 * sqrt(15/Pi)
#define kSHBasis3  0.31539156525252000603f // {2, 0} : 1/4 * sqrt(5/Pi)
#define kSHBasis4  0.54627421529603953527f // {2, 2} : 1/4 * sqrt(15/Pi)

// Ref: "Efficient Evaluation of Irradiance Environment Maps" from ShaderX 2
half3 SHEvalLinearL0L1(half3 N, half4 shAr, half4 shAg, half4 shAb)
{
    half4 vA = half4(N, 1.0);

    half3 x1;
    // Linear (L1) + constant (L0) polynomial terms
    x1.r = dot(shAr, vA);
    x1.g = dot(shAg, vA);
    x1.b = dot(shAb, vA);

    return x1;
}

half3 SHEvalLinearL2(half3 N, half4 shBr, half4 shBg, half4 shBb, half4 shC)
{
    half3 x2;
    // 4 of the quadratic (L2) polynomials
    half4 vB = N.xyzz * N.yzzx;
    x2.r = dot(shBr, vB);
    x2.g = dot(shBg, vB);
    x2.b = dot(shBb, vB);

    // Final (5th) quadratic (L2) polynomial
    half vC = N.x * N.x - N.y * N.y;
    half3 x3 = shC.rgb * vC;

    return x2 + x3;
}

half3 SampleSH9(half4 SHCoefficients[7], half3 N)
{
    half4 shAr = SHCoefficients[0];
    half4 shAg = SHCoefficients[1];
    half4 shAb = SHCoefficients[2];
    half4 shBr = SHCoefficients[3];
    half4 shBg = SHCoefficients[4];
    half4 shBb = SHCoefficients[5];
    half4 shCr = SHCoefficients[6];

    // Linear + constant polynomial terms
    half3 res = SHEvalLinearL0L1(N, shAr, shAg, shAb);

    // Quadratic polynomials
    res += SHEvalLinearL2(N, shBr, shBg, shBb, shCr);

    return res;
}

float3 SampleSH9(StructuredBuffer<float4> data, float3 N)
{
    half4 shAr = data[0];
    half4 shAg = data[1];
    half4 shAb = data[2];
    half4 shBr = data[3];
    half4 shBg = data[4];
    half4 shBb = data[5];
    half4 shCr = data[6];

    // Linear + constant polynomial terms
    half3 res = SHEvalLinearL0L1(N, shAr, shAg, shAb);

    // Quadratic polynomials
    res += SHEvalLinearL2(N, shBr, shBg, shBb, shCr);

    return res;
}

#endif