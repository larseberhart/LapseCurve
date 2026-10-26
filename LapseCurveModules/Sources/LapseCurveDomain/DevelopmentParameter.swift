/// Lightroom global development parameters considered by the interpolation engine.
public enum DevelopmentParameter: String, Codable, CaseIterable, Sendable {
    /// Exposure compensation in stops.
    case exposure
    /// Global contrast adjustment.
    case contrast
    /// Highlight-tone adjustment.
    case highlights
    /// Shadow-tone adjustment.
    case shadows
    /// White-point adjustment.
    case whites
    /// Black-point adjustment.
    case blacks
    /// White-balance temperature.
    case temperature
    /// White-balance tint.
    case tint
    /// Color vibrance adjustment.
    case vibrance
    /// Global color saturation adjustment.
    case saturation
    /// Fine-detail texture adjustment.
    case texture
    /// Midtone clarity adjustment.
    case clarity
    /// Atmospheric haze adjustment.
    case dehaze
    case parametricShadows
    case parametricDarks
    case parametricLights
    case parametricHighlights
    case parametricShadowSplit
    case parametricMidtoneSplit
    case parametricHighlightSplit
    case sharpness
    case sharpenRadius
    case sharpenDetail
    case sharpenEdgeMasking
    case luminanceSmoothing
    case luminanceNoiseReductionDetail
    case luminanceNoiseReductionContrast
    case colorNoiseReduction
    case colorNoiseReductionDetail
    case colorNoiseReductionSmoothness
    case hueAdjustmentRed
    case hueAdjustmentOrange
    case hueAdjustmentYellow
    case hueAdjustmentGreen
    case hueAdjustmentAqua
    case hueAdjustmentBlue
    case hueAdjustmentPurple
    case hueAdjustmentMagenta
    case saturationAdjustmentRed
    case saturationAdjustmentOrange
    case saturationAdjustmentYellow
    case saturationAdjustmentGreen
    case saturationAdjustmentAqua
    case saturationAdjustmentBlue
    case saturationAdjustmentPurple
    case saturationAdjustmentMagenta
    case luminanceAdjustmentRed
    case luminanceAdjustmentOrange
    case luminanceAdjustmentYellow
    case luminanceAdjustmentGreen
    case luminanceAdjustmentAqua
    case luminanceAdjustmentBlue
    case luminanceAdjustmentPurple
    case luminanceAdjustmentMagenta
    case splitToningShadowHue
    case splitToningShadowSaturation
    case splitToningHighlightHue
    case splitToningHighlightSaturation
    case splitToningBalance
    case colorGradeMidtoneHue
    case colorGradeMidtoneSat
    case colorGradeShadowLum
    case colorGradeMidtoneLum
    case colorGradeHighlightLum
    case colorGradeBlending
    case colorGradeGlobalHue
    case colorGradeGlobalSat
    case colorGradeGlobalLum
    case autoLateralCA
    case lensProfileEnable
    case lensManualDistortionAmount
    case vignetteAmount
    case defringePurpleAmount
    case defringePurpleHueLo
    case defringePurpleHueHi
    case defringeGreenAmount
    case defringeGreenHueLo
    case defringeGreenHueHi
    case perspectiveUpright
    case perspectiveVertical
    case perspectiveHorizontal
    case perspectiveRotate
    case perspectiveAspect
    case perspectiveScale
    case perspectiveX
    case perspectiveY
    case grainAmount
    case glow
    case postCropVignetteAmount
    case shadowTint
    case redHue
    case redSaturation
    case greenHue
    case greenSaturation
    case blueHue
    case blueSaturation
}