using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

public class TrapezoidSector : MonoBehaviour
{
    [Range(-1.0f, 1.0f)] public float occluderMeanZ = 0.0f;
    [Range(0.1f, 2.0f)] public float occluderMeanY = 1.0f;
    [Range(0.0001f, 1.0f)] public float occluderStdZ = 0.01f;
    [Range(0.5f, 40.0f)] public float occluderThickness = 40.0f;

    struct Trapezoid
    {
        public float median;
        public float constHalfSize;
        public float linHalfSize;
        public float height;
    }

    float LinearIntegral(float x)
    {
        return x * x * 0.5f;
    }

    Trapezoid GetVarianceTrapezoid(float2 minMax, float sigma0)
    {
        Trapezoid result;
        float halfRange = math.sqrt(3.0f) * sigma0;
        float halfSize = (minMax.y - minMax.x) * 0.5f;
        result.median = 0.5f * (minMax.x + minMax.y);
        result.constHalfSize = math.abs(halfSize - halfRange);
        result.linHalfSize = math.max(0.00001f, halfSize + halfRange - result.constHalfSize);
        result.height = math.min(1.0f, halfSize / math.max(0.00001f, halfRange));
        return result;
    }

    float IntegrateTrapezoid(Trapezoid trapezoid, float x)
    {
        float constRange = math.min(math.abs(x - trapezoid.median), trapezoid.constHalfSize + trapezoid.linHalfSize);
        float linRange = math.max(0.0f, constRange - trapezoid.constHalfSize);
        float constInt = constRange;
        float linInt = -LinearIntegral(linRange) / trapezoid.linHalfSize;
        return (x > trapezoid.median ? 1.0f : -1.0f) * trapezoid.height * (constInt + linInt);
    }

    float[] ComputeSectorTransmittance(Trapezoid trapezoid, float sharpness)
    {
        var transmittances = new float[16];

        var prevOcclusion = IntegrateTrapezoid(trapezoid, 0.0f);

        for (int rayId = 0; rayId < 16; rayId++)
        {
            var alpha = (rayId + 1.0f) * (1.0f / 16.0f);
            var theta = (rayId + 1.0f) * (Mathf.PI / 16.0f);
            // alpha = 0.5f - 0.5f * Mathf.Cos(theta); // same domain as occluderMean/Upper/Thick

            var occlusion = IntegrateTrapezoid(trapezoid, alpha);
            var transmittance = math.saturate(math.pow(math.saturate(1.0f - (occlusion - prevOcclusion) * 16.0f), sharpness));
            prevOcclusion = occlusion;

            transmittances[rayId] = transmittance;
        }

        return transmittances;
    }

    private void OnDrawGizmos()
    {
#if UNITY_EDITOR
        Gizmos.matrix = transform.localToWorldMatrix;
        UnityEditor.Handles.matrix = transform.localToWorldMatrix;
        UnityEditor.Handles.zTest = CompareFunction.LessEqual;

        var occluderMeanVS = new Vector3(0.0f, occluderMeanY, occluderMeanZ);
        var occluderUpperVS = new Vector3(0.0f, occluderMeanY, occluderMeanZ + occluderStdZ);
        var occluderThickVS = new Vector3(0.0f, occluderMeanY, occluderMeanZ + occluderThickness);

        var oclluderStdAngle = Vector3.Angle(occluderMeanVS, occluderUpperVS);
        var oclluderAngle = Vector3.Angle(occluderUpperVS, occluderThickVS);

        var occluderMean = occluderMeanVS.normalized.z * 0.5f + 0.5f;
        var occluderUpper = occluderUpperVS.normalized.z * 0.5f + 0.5f;
        var occluderThick = occluderThickVS.normalized.z * 0.5f + 0.5f;

        float sigma = math.max(0.00001f, occluderUpper - occluderMean);

        float2 minMax;
        minMax.x = occluderUpper;
        minMax.y = occluderThick;

        var trapezoid = GetVarianceTrapezoid(minMax, sigma);
        var transmittance = ComputeSectorTransmittance(trapezoid, 0.25f);

        DrawSectors(transmittance, 0.1f);
        DrawOccluder(occluderMeanVS, occluderUpperVS, oclluderStdAngle, oclluderAngle, 0.25f);

        UnityEditor.Handles.zTest = CompareFunction.Always;

        DrawSectors(transmittance, 0.02f);
        DrawOccluder(occluderMeanVS, occluderUpperVS, oclluderStdAngle, oclluderAngle, 0.02f);

        for (int i = 0; i < 16; i++)
        {
            float alpha = (i + 0.5f) / 16.0f * Mathf.PI;
            var direction = Vector3.zero;
            direction.y = Mathf.Sin(alpha);
            direction.z = -Mathf.Cos(alpha);

            var length = transmittance[i];

            UnityEditor.Handles.Label(direction * (length + 0.08f), $"{i}");
        }

        Gizmos.color = Color.white;
        Gizmos.DrawLine(occluderMeanVS, occluderThickVS);
        Gizmos.DrawSphere(occluderMeanVS, 0.01f);
        Gizmos.DrawSphere(occluderUpperVS, 0.01f);
        Gizmos.DrawSphere(occluderThickVS, 0.01f);
#endif
    }

    private void DrawOccluder(Vector3 occluderMeanVS, Vector3 occluderUpperVS, float occluderStdAngle, float occluderAngle, float colorAlpha)
    {
        UnityEditor.Handles.color = new Color(0.0f, 0.0f, 0.9f, colorAlpha);
        UnityEditor.Handles.DrawSolidArc(Vector3.zero, Vector3.right, occluderMeanVS, occluderStdAngle, 1.1f);
        UnityEditor.Handles.color = new Color(0.0f, 0.2f, 0.9f, colorAlpha);
        UnityEditor.Handles.DrawSolidArc(Vector3.zero, Vector3.right, occluderUpperVS, occluderAngle, 1.1f);
    }

    private static void DrawSectors(float[] transmittance, float colorAlpha)
    {
        for (int i = 0; i < 16; i++)
        {
            float alpha = i / 16.0f * Mathf.PI;
            var direction = Vector3.zero;
            direction.y = Mathf.Sin(alpha);
            direction.z = -Mathf.Cos(alpha);

            var length = transmittance[i];

            UnityEditor.Handles.color = new Color(1.0f, 1.0f, 1.0f, colorAlpha);
            UnityEditor.Handles.DrawSolidArc(Vector3.zero, Vector3.right, direction, 180.0f / 16.0f, length);

            Gizmos.color = Color.red;
            Gizmos.DrawRay(Vector3.zero, direction * length);
        }
    }
}