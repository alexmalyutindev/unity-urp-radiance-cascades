using AlexMalyutinDev.RadianceCascades;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Serialization;

#if UNITY_EDITOR
using UnityEditor;

public class RaysDistribution : MonoBehaviour
{
    [MinMax(0, 5)]
    public Vector2Int CascadeRange = new(0, 3);

    private void OnDrawGizmosSelected()
    {
        var rayScale = VolumeManager.instance.stack.GetComponent<RadianceCascades>().RayScale.value;

        var camera = SceneView.currentDrawingSceneView.camera;
        var cameraTransform = camera.transform;

        for (int cascadeLevel = CascadeRange.x; cascadeLevel <= CascadeRange.y; cascadeLevel++)
        {
            Gizmos.color = Color.HSVToRGB(cascadeLevel / 6.0f, 1.0f, 1.0f);

            float deltaPhi = 2 * Mathf.PI * Mathf.Pow(0.5f, cascadeLevel) * 0.25f; // 1/4
            float deltaTheta = Mathf.PI * 0.25f;

            for (int x = 0; x < 8 * (1 << cascadeLevel); x++)
            {
                for (int y = 0; y < 4; y++)
                {
                    float phi = (x + 0.5f) * deltaPhi;
                    float theta = (y + 0.5f) * deltaTheta;

                    var sinCosPhi = new Vector2(Mathf.Sin(phi), Mathf.Cos(phi));
                    var sinCosTheta = new Vector2(Mathf.Sin(theta), Mathf.Cos(theta));

                    var direction = new Vector3(
                        sinCosTheta.x * sinCosPhi.y,
                        sinCosTheta.x * sinCosPhi.x,
                        sinCosTheta.y
                    );

                    direction = cameraTransform.TransformDirection(direction) * rayScale;
                    float rayOriginOffset = cascadeLevel == 0 ? 0 : 1 << (cascadeLevel - 1);
                    float rayLenght = (1 << cascadeLevel) - rayOriginOffset;

                    Gizmos.DrawRay(
                        transform.position + direction * rayOriginOffset,
                        direction * rayLenght
                    );
                }
            }
        }
    }
}

public class MinMaxAttribute : PropertyAttribute
{
    public readonly int Min;
    public readonly int Max;

    public MinMaxAttribute(int min, int max)
    {
        Min = min;
        Max = max;
    }
}

[CustomPropertyDrawer(typeof(MinMaxAttribute))]
public class MinMaxPropertyDrawer : PropertyDrawer
{
    public override void OnGUI(Rect position, SerializedProperty property, GUIContent label)
    {
        if (attribute is not MinMaxAttribute minMax)
        {
            return;
        }
        
        var value = property.vector2IntValue;
        float min = value.x;
        float max = value.y;
        
        var valuePreview = new GUIContent($"[{min} - {max}]");
        var valueSize = EditorStyles.label.CalcSize(valuePreview);
        valueSize.x += EditorGUIUtility.standardVerticalSpacing;

        EditorGUI.BeginChangeCheck();
        var rect0 = new Rect(position)
        {
            width = position.width - valueSize.x - EditorGUIUtility.standardVerticalSpacing,
        };
        EditorGUI.MinMaxSlider(rect0, label, ref min, ref max, minMax.Min, minMax.Max);

        var rect1 = new Rect(rect0)
        {
            x = rect0.x + rect0.width,
            width = valueSize.x,
        };

        GUI.Label(rect1,  valuePreview);

        if (EditorGUI.EndChangeCheck())
        {
            property.vector2IntValue = new Vector2Int(Mathf.RoundToInt(min), Mathf.RoundToInt(max));
        }
    }
}

#endif
