using System;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Serialization;

public class TrapezoidSector : MonoBehaviour
{
    public float occluderMeanZ = 0.0f;
    [Range(0.00001f, 1.0f)] public float occluderStdZ = 0.01f;
    public float occluderThickness = 40.0f;

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

        float prevOcclusion = IntegrateTrapezoid(trapezoid, 0.0f);

        for (int rayId = 0; rayId < 16; rayId++)
        {
            float alpha = (rayId + 1.0f) * (1.0f / 16.0f);

            float occlusion = IntegrateTrapezoid(trapezoid, alpha);
            float transmittance =
                math.saturate(math.pow(math.saturate(1.0f - (occlusion - prevOcclusion) * 16.0f), sharpness));
            prevOcclusion = occlusion;

            transmittances[rayId] = transmittance;
        }

        return transmittances;
    }

    private void OnDrawGizmos()
    {
        Gizmos.matrix = transform.localToWorldMatrix;

        var occluderMeanVS = new Vector3(0.0f, 1.0f, occluderMeanZ);
        var occluderUpperVS = new Vector3(0.0f, 1.0f, occluderMeanZ + occluderStdZ);
        var occluderThickVS = new Vector3(0.0f, 1.0f, occluderMeanZ + occluderThickness);

        var oclluderStdAngle = Vector3.Angle(occluderMeanVS, occluderUpperVS);
        var oclluderAngle = Vector3.Angle(occluderUpperVS, occluderThickVS);

        var occluderMean = occluderMeanVS.normalized.z * 0.5f + 0.5f;
        var occluderUpper = occluderUpperVS.normalized.z * 0.5f + 0.5f;
        var occluderThick = occluderThickVS.normalized.z * 0.5f + 0.5f;

        float2 minmax;
        minmax.x = occluderUpper;
        minmax.y = occluderThick;

        float sigma = occluderUpper - occluderMean;

        var trapezoid = GetVarianceTrapezoid(minmax, sigma);

        var transmittance = ComputeSectorTransmittance(trapezoid, 0.5f);

#if UNITY_EDITOR
        for (int i = 0; i < 16; i++)
        {
            float alpha = i / 16.0f * Mathf.PI;
            var direction = Vector3.zero;
            direction.y = Mathf.Sin(alpha);
            direction.z = Mathf.Cos(alpha);

            var length = transmittance[i];

            UnityEditor.Handles.color = new Color(length, length, length, 1.0f);
            UnityEditor.Handles.DrawSolidArc(Vector3.zero, -Vector3.right, direction, 180.0f / 16.0f, length);

            Gizmos.color = Color.black;
            Gizmos.DrawRay(Vector3.zero, direction * length);

            Vector3 labelPos = transform.TransformPoint(direction * (length + 0.08f));
            UnityEditor.Handles.Label(labelPos, $"{i}");
        }
#endif

        Gizmos.DrawLine(occluderMeanVS, occluderThickVS);
        Gizmos.DrawSphere(occluderMeanVS, 0.01f);
        Gizmos.DrawSphere(occluderUpperVS, 0.01f);
        Gizmos.DrawSphere(occluderThickVS, 0.01f);

#if UNITY_EDITOR
        UnityEditor.Handles.matrix = transform.localToWorldMatrix;
        UnityEditor.Handles.color = new Color(0.0f, 0.0f, 0.9f, 0.5f);
        UnityEditor.Handles.DrawSolidArc(Vector3.zero, Vector3.right, occluderMeanVS, oclluderStdAngle, 10.0f);
        UnityEditor.Handles.color = new Color(0.0f, 0.2f, 0.9f, 0.5f);
        UnityEditor.Handles.DrawSolidArc(Vector3.zero, Vector3.right, occluderUpperVS, oclluderAngle, 10.0f);
#endif
    }
}