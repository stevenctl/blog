---
title: Triplanar with Deep Parallax in Godot
date: 2022-12-23
type: tech
tags: ["gamedev", "godot", "shaders", "graphics"]
---

Triplanar mapping is already expensive, and multiplying that by the samples for
paralax occlusion mapping is probably a bad idea. It was fun to implement this
anyway, even if I don't use it in a game.

In my current WFC prototypes, I'm re-using models and rotating them. At some
point I'll need to handle also transforming the UVs based on the rotation of
the tiles' models, but for now triplanar mapping is a quick way to get an idea
of how things might look.

I want to use heightmaps to add details without extra geometry. The concern is
mostly on my workflow, not on performance. I'm simply too lazy to model that into
my modules in a tileable way.

The effect is turned up a bit to make it extra apparent int the images here.
The floor shouldn't be offset so strongly if you want to have a character walk
on it without them appearing to levitate.

## Heightmap with Deep Parallax

{{<video "pom.webm">}}

## Normal Map Only

{{<video "norm.webm">}}

Using Ben Golus's basic "swizzle" from his
[Normal Mapping for a Triplanar
Shader](https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a)
tutorial, and I think the results are just fine.

## The Shader

It's mostly gluing code from various tutorials together. Also there's some
unnessary conditionals I have for toggling the ability to use two sets of
textures for the walls and floor. In reality there should be a separate shader
for each, or some preprocessor stuff instead of a runtime check.

```c
shader_type spatial;

uniform float blendSharpness;

uniform sampler2D textureMap : source_color;
uniform sampler2D normalMap : hint_normal;
uniform sampler2D heightMap : hint_default_white;
uniform float normalMapStrength : hint_range(0, 1) = 1.0;
uniform float uvScale = 1.0;

uniform bool enableFloor = false;
uniform sampler2D floorTextureMap : source_color;
uniform sampler2D floorNormalMap : hint_normal;
uniform sampler2D floorHeightMap : hint_default_white;
uniform float floorUvScale = 1.0;

uniform bool enablePom = true;
uniform int heightMinLayers = 8;
uniform int heightMaxLayers = 64;
uniform float heightScale = 1.0;

varying vec3 worldPos;
varying vec3 worldNormal;


void vertex() {
	 // Transform the vertex position to world space
    worldPos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // Transform the vertex normal to world space
    worldNormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

}

// TODO conditionals...
vec2 scaleUV(float yDot, vec2 uv) {
  return uv * (enableFloor && yDot > 0.0 ? floorUvScale : uvScale);
}

// TODO conditionals...
vec4 sampleColor(float yDot, vec2 uv) {
  return enableFloor && yDot > 0.0 ? texture(floorTextureMap, uv) : texture(textureMap, uv);
}

// TODO conditionals...
vec4 sampleHeight(float yDot, vec2 uv) {
  return enableFloor && yDot > 0.0 ? texture(floorHeightMap, uv) : texture(heightMap, uv);
}

// TODO conditionals...
vec4 sampleNormal(float yDot, vec2 uv) {
  return enableFloor && yDot > 0.0 ? texture(floorNormalMap, uv) : texture(normalMap, uv);
}

vec4 triplanarSample(vec2 uvX, vec2 uvY, vec2 uvZ, vec3 blend, float yDot) {
    // Sample the texture using the calculated texture coordinates
    vec4 texColorX = texture(textureMap, uvX);
    vec4 texColorY = sampleColor(yDot, uvY);
    vec4 texColorZ = texture(textureMap, uvZ);

    // Blend the samples together
    return texColorX * blend.x
            + texColorY * blend.y
            + texColorZ * blend.z;
}

// The simplest appoach suggested in the goat's article:
// https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a
vec3 triplanarNormal(float yDot, vec2 uvX, vec2 uvY, vec2 uvZ, vec3 blend) {

    // Tangent space normal maps
    vec3 tnormalX = texture(normalMap, uvX).rgb;
    vec3 tnormalY = sampleNormal(yDot, uvY).rgb;
    vec3 tnormalZ = texture(normalMap, uvZ).rgb;

    // Get the sign (-1 or 1) of the surface normal
    vec3 axisSign = sign(worldNormal);



    // Flip tangent normal z to account for surface normal facing
    tnormalX.z *= axisSign.x;
    tnormalY.z *= axisSign.y;
    tnormalZ.z *= axisSign.z;

    // Swizzle tangent normals to match world orientation and triblend
    return normalize(
      tnormalX.zyx * blend.x +
      tnormalY.xzy * blend.y +
      tnormalZ.xyz * blend.z
    );

}

// Adapted from the tutorial. Changed to accept a viewDir which represents each plane.
// https://www.youtube.com/watch?v=LrnE5f3h2SU
vec2 pomUV(float yDot, vec2 m_base_uv, vec3 viewDir) {
    float viewDot = dot(viewDir, vec3(1, 0, 0));
    float minLayers = float(min(heightMinLayers, heightMaxLayers));
    float maxLayers = float(max(heightMinLayers, heightMaxLayers));
    float numLayers = mix(maxLayers, minLayers, abs(viewDot));
    numLayers = clamp(numLayers, minLayers, maxLayers);
    float layerDepth = 1.0f / numLayers;

    vec2 uvOffset = viewDir.xy * heightScale / numLayers;

    // tracks how "deep" we are on each iteration
    float currentLayerDepth = 0.0;
    // tracks how deep the heightmap; adjusted on each iteration as UVs shift
    float depthMapValue = 1.0 - sampleHeight(yDot, m_base_uv).r;

    // loop until the current layer is deeper than the heightmap (hit)
    // the 100 iteration cap is because I'm paranoid
    for (int i = 0; i < 100 && currentLayerDepth < depthMapValue; i++) {
        m_base_uv -= uvOffset;
        depthMapValue = 1.0 - sampleHeight(yDot, m_base_uv).r;
        currentLayerDepth += layerDepth;
    }

    // occlusion (interpolate with prev value)
    vec2 prevUV = m_base_uv + uvOffset;
    float afterDepth =  depthMapValue - currentLayerDepth;
    float beforeDepth = 1.0 - sampleHeight(yDot, prevUV).r - currentLayerDepth + layerDepth;
    float weight = afterDepth / (afterDepth - beforeDepth);
    m_base_uv = prevUV * weight + m_base_uv * (1.0 - weight);

    return m_base_uv;
}

void fragment() {
    // Calculate blending
    float yDot = dot(worldNormal, vec3(0.0, 1.0, 0.0));
    vec3 blend = vec3(
        smoothstep(blendSharpness, 1.0, abs(dot(worldNormal, vec3(1.0, 0.0, 0.0)))),
        smoothstep(blendSharpness, 1.0, abs(yDot)),
        smoothstep(blendSharpness, 1.0, abs(dot(worldNormal, vec3(0.0, 0.0, 1.0))))
    );

    // view dir will be swizzled to match coordinates
    vec3 viewDir = normalize(CAMERA_POSITION_WORLD - worldPos);

    // Calculate texture coordinates
    vec2 texCoordX = worldPos.zy * uvScale;
    vec2 texCoordY = scaleUV(yDot, worldPos.zx);
    vec2 texCoordZ = worldPos.xy * uvScale;
    // TODO conditionals...
    if (enablePom) {
      texCoordX = pomUV(yDot, texCoordX, viewDir.zyx);
      texCoordY = pomUV(yDot, texCoordY, viewDir.zxy);
      texCoordZ = pomUV(yDot, texCoordZ, viewDir.xyz);
    }

    // sample and output
    ALBEDO = triplanarSample(texCoordX, texCoordY, texCoordZ, blend, yDot).rgb;
    NORMAL = mix(worldNormal, triplanarNormal(yDot, texCoordX, texCoordY, texCoordZ, blend), normalMapStrength);
    NORMAL = normalize((VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
```
