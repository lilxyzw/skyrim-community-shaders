/*
Copyright (c) 2025 lilxyzw

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.

3. This notice may not be removed or altered from any source distribution.
*/

#define lil_p_EyeSpecular 6
#define lil_p_HairIntensity 0.75
#define lil_p_DirLightIntensityDay 2.0
#define lil_p_DirLightIntensityNight 0.5
#define lil_p_DirLightDesaturationDay 0.0
#define lil_p_DirLightDesaturationNight 0.0
#define lil_p_NonDirectionalLight float3(1.0,0.7,0.5) * 0.05
#define lil_p_CharacterLight 0.2
#define lil_p_CharacterEyeLight 0.2
#define lil_p_InteriorBoost 1.5
#define lil_p_SkyBoost lil_MultFromDirLight(SharedData::DirLightColor.xyz)
#define lil_p_FogBoost lil_MultFromDirLight(SharedData::DirLightColor.xyz)
#define lil_DOF_SAMPLE_COUNT 32
#define lil_DOF_RADIUS 0.0075
#define lil_BLOOM_SAMPLE_COUNT 24
#define lil_BLOOM_RADIUS 0.075

float lil_warmth(float3 rgb)
{
    return saturate(rgb.r / rgb.r * 4 - rgb.b / rgb.r * 3);
}

float lil_luminance(float3 rgb)
{
    return dot(rgb, float3(0.2,0.7,0.1));
}

float lil_desaturation(float3 rgb, float desat)
{
    return lerp(lil_luminance(rgb), rgb, desat);
}

float3 lil_DirLightModify(float3 rgb)
{
    float warmth = lil_warmth(rgb);
    float intensity = lerp(lil_p_DirLightIntensityNight, lil_p_DirLightIntensityDay, warmth);
    float desaturation = lerp(lil_p_DirLightDesaturationNight, lil_p_DirLightDesaturationDay, warmth);
    rgb *= intensity;
    rgb = lil_desaturation(rgb, desaturation);
    return rgb;
}

float lil_MultFromDirLight(float3 rgb)
{
    float warmth = lil_warmth(rgb);
    float intensity = lerp(lil_p_DirLightIntensityNight, lil_p_DirLightIntensityDay, warmth);
    return intensity;
}

float2 lil_Aspect()
{
    float aspect = FrameBuffer::CameraProj[0]._m00 / FrameBuffer::CameraProj[0]._m11;
    return float2(aspect,1);
}

float lil_Autofocus(Texture2D DepthTex, SamplerState DepthSampler)
{
    float near = 0;
    near =     DepthTex.Sample(DepthSampler, float2(0.4,0.4)).r;
    near = min(DepthTex.Sample(DepthSampler, float2(0.5,0.4)).r, near);
    near = min(DepthTex.Sample(DepthSampler, float2(0.6,0.4)).r, near);
    near = min(DepthTex.Sample(DepthSampler, float2(0.4,0.5)).r, near);
    near = min(DepthTex.Sample(DepthSampler, float2(0.5,0.5)).r, near);
    near = min(DepthTex.Sample(DepthSampler, float2(0.6,0.5)).r, near);
    near = min(DepthTex.Sample(DepthSampler, float2(0.4,0.6)).r, near);
    near = min(DepthTex.Sample(DepthSampler, float2(0.5,0.6)).r, near);
    near = min(DepthTex.Sample(DepthSampler, float2(0.6,0.6)).r, near);
    near += 0.02;
    return near;
}

float3 lil_DOFBlur(Texture2D ColorTex, SamplerState ColorSampler, Texture2D BlurTex, SamplerState BlurSampler, Texture2D DepthTex, SamplerState DepthSampler, float2 uv)
{
    float near = lil_Autofocus(DepthTex, DepthSampler);
    float far = near + 0.05;

    float si,co;
    sincos(2.39996, si, co);
    float r = 1.0;
    float rmax = 1.0;
    float2 v = float2(lil_DOF_RADIUS,0.0);
    float2 f = lil_Aspect();
    [unroll]
    for(int j = 0; j < lil_DOF_SAMPLE_COUNT; j++)
    {
        rmax += rcp(rmax);
    }
    rmax -= 1.0;

    float3 sumCol = ColorTex.Sample(ColorSampler, uv).rgb;
    float3 maxCol = sumCol;
    float3 pixelCol = ColorTex.Sample(ColorSampler, uv).rgb;
    float sum = 1;
    [unroll]
    for(int l = 0; l < lil_DOF_SAMPLE_COUNT; l++)
    {
        r = r + rcp(r);
        v = float2(
            v.x * co - v.y * si,
            v.x * si + v.y * co
        );
        float r2 = (r-1.0) / rmax;
        float2 temp_uv = uv + r2 * f * v;
        float3 temp_col = ColorTex.Sample(ColorSampler, temp_uv).rgb;
        float temp_depth = DepthTex.Sample(DepthSampler, temp_uv).r;
        float factor = saturate((temp_depth - near) / (far - near));
        factor *= factor;
        factor = factor > r2;
        temp_col *= factor;
        maxCol = max(maxCol, temp_col);
        sumCol += temp_col * r;
        sum += r * factor;
    }
    sumCol /= sum;
    float3 orig_col = ColorTex.Sample(ColorSampler, uv).rgb;
    float orig_depth = DepthTex.Sample(DepthSampler, uv).r;
    // Outputting this to a render target and blurring it slightly should make the artifacts less noticeable.
    float3 finalCol = lerp(sumCol, maxCol, 0.25);
    finalCol = lerp(orig_col, finalCol, saturate((orig_depth - near)*50));
    return finalCol;
}

float lil_Adaptation(float avg)
{
    return clamp(avg * 2.2, 0.5, 1000.0) + 0.3;
}

float3 lil_BloomBlur(Texture2D BloomTex, SamplerState BloomSampler, float2 uv, float avg)
{
    // It looks complicated, but it is unrolled and optimized at compile time.
    float3 pixelCol = 0;
    float3 sum = 0;
    float si,co;
    sincos(2.39996, si, co);
    float r = 1.0;
    float rmax = 1.0;
    float2 v = float2(lil_BLOOM_RADIUS,0.0);
    float2 f = lil_Aspect();
    [unroll]
    for(int j = 0; j < lil_BLOOM_SAMPLE_COUNT; j++)
    {
        rmax += rcp(rmax);
    }
    rmax -= 1.0;
    [unroll]
    for(int k = 0; k < lil_BLOOM_SAMPLE_COUNT; k++)
    {
        r = r + rcp(r);
        float r2 = r-1.0;
        sum += exp(-r2*r2/(rmax*rmax/2.0));
    }
    r = 1.0;
    [unroll]
    for(int l = 0; l < lil_BLOOM_SAMPLE_COUNT; l++)
    {
        r = r + rcp(r);
        v = float2(
            v.x * co - v.y * si,
            v.x * si + v.y * co
        );
        float r2 = r-1.0;
        float blend = exp(-r2*r2/(rmax*rmax/2.0)) / sum;
        pixelCol += saturate(BloomTex.Sample(BloomSampler, uv + r2 / rmax * f * v).rgb - avg * 1.5) * blend;
    }
    return pixelCol * 3;
}

float3 lil_PostProcess(float3 rgb, float2 uv, float3 bloom, float avg, bool inInterior)
{
    // Bloom
	rgb += (bloom * 0.15 + dot(bloom,0.03)) * saturate(avg*1.5-dot(rgb, 0.333333));

    // Adaptation
    float adp = lil_Adaptation(avg);
    rgb /= adp;

    // Vignette
    float vig = distance(uv, 0.5);
    vig = saturate(1 - vig * 1.25);
    rgb *= sqrt(vig);

    if(inInterior) rgb *= lil_p_InteriorBoost;

    // Tonemapping
    rgb = 1.1 - saturate(rcp(rgb*4+1)) * 1.1;
    rgb *= rgb * 0.7 + 0.3;

    return saturate(rgb);
}
