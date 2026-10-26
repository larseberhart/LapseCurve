import Foundation
import LapseCurveDomain

/// Experimental Camera Raw mappings from the supplied sample and user-requested field list.
public enum XMPFieldRegistry {
    /// Namespace URI for Camera Raw settings properties.
    public static let cameraRawSettingsNamespace = "http://ns.adobe.com/camera-raw-settings/1.0/"
    /// Namespace URI for the camera-specific defaults Lightroom records alongside settings.
    public static let cameraRawDefaultsNamespace = "http://ns.adobe.com/camera-raw-defaults/1.0/"

    /// Lightroom's built-in value for fields absent from both `crs:` and `crd:`; unlisted fields default to 0.
    public static let lightroomDefaultValues: [DevelopmentParameter: Double] = [
        .parametricShadowSplit: 25,
        .parametricMidtoneSplit: 50,
        .parametricHighlightSplit: 75,
        .colorGradeBlending: 50,
        .sharpness: 40,
        .sharpenRadius: 1,
        .sharpenDetail: 25,
        .luminanceNoiseReductionDetail: 50,
        .colorNoiseReduction: 25,
        .colorNoiseReductionDetail: 50,
        .colorNoiseReductionSmoothness: 50,
        .defringePurpleHueLo: 30,
        .defringePurpleHueHi: 70,
        .defringeGreenHueLo: 40,
        .defringeGreenHueHi: 60
    ]

    /// As-shot white balance differs per photo, so it has no neutral value to assume.
    public static let parametersWithoutDefault: Set<DevelopmentParameter> = [.temperature, .tint]

    private static let signedParameters: Set<DevelopmentParameter> = [
        .exposure, .contrast, .highlights, .shadows, .whites, .blacks, .tint,
        .vibrance, .saturation, .texture, .clarity, .dehaze, .sharpenRadius
    ]

    /// Serializes a value with Lightroom's precision for the field.
    public static func formattedValue(_ value: Double, for parameter: DevelopmentParameter) -> String {
        let decimalPlaces: Int
        switch parameter {
        case .exposure:
            decimalPlaces = 2
        case .sharpenRadius:
            decimalPlaces = 1
        default:
            decimalPlaces = 0
        }
        let scale = pow(10, Double(decimalPlaces))
        var rounded = (value * scale).rounded() / scale
        if rounded == 0 { rounded = 0 }
        let text = String(format: "%.\(decimalPlaces)f", rounded)
        return rounded > 0 && signedParameters.contains(parameter) ? "+\(text)" : text
    }

    /// Resolves the values Lightroom renders: `crs:` first, then the `crd:` camera defaults, then Lightroom's defaults.
    public static func developmentValues(
        in packet: XMPPacket,
        definitions: [ParameterDefinition] = candidateDevelopmentParameters
    ) -> (parameters: ParameterSet, issues: [ValidationIssue]) {
        var parameters = ParameterSet()
        var issues: [ValidationIssue] = []
        for definition in definitions {
            let settings = packet.properties.filter {
                $0.namespaceURI == definition.namespaceURI && $0.localName == definition.xmpTag
            }
            if settings.count > 1 {
                issues.append(ValidationIssue(
                    severity: .warning,
                    code: "xmpDevelopmentPropertyDuplicate",
                    message: "The sidecar has duplicate values for \(definition.xmpTag); the value was not imported.",
                    parameter: definition.parameter
                ))
                continue
            }
            if let setting = settings.first {
                guard let value = numericValue(setting.value) else {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        code: "xmpDevelopmentPropertyInvalid",
                        message: "The sidecar value for \(definition.xmpTag) is not numeric; the value was not imported.",
                        parameter: definition.parameter
                    ))
                    continue
                }
                parameters.values[definition.parameter] = ParameterSample(
                    value: value,
                    origin: .importedSidecar,
                    isLocked: false
                )
                continue
            }

            guard !parametersWithoutDefault.contains(definition.parameter) else { continue }
            let cameraDefaults = packet.properties.filter {
                $0.namespaceURI == cameraRawDefaultsNamespace && $0.localName == definition.xmpTag
            }
            let cameraDefault = cameraDefaults.count == 1 ? numericValue(cameraDefaults[0].value) : nil
            parameters.values[definition.parameter] = ParameterSample(
                value: cameraDefault ?? lightroomDefaultValues[definition.parameter] ?? 0,
                origin: .assumedNeutral,
                isLocked: false
            )
        }
        let whiteBalanceMode = packet.properties.first {
            $0.namespaceURI == cameraRawSettingsNamespace && $0.localName == whiteBalanceModeTag
        }?.value
        if whiteBalanceMode == "As Shot" {
            for parameter in parametersWithoutDefault {
                parameters.values[parameter]?.origin = .asShot
            }
        }
        return (parameters, issues)
    }

    private static func numericValue(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            return nil
        }
        return value
    }

    /// Candidate scalar controls enabled for explicitly confirmed writes; ranges and Adobe read-back remain unverified.
    public static let candidateDevelopmentParameters: [ParameterDefinition] = [
        definition(.exposure, tag: "Exposure2012", unit: .exposureEV),
        definition(.contrast, tag: "Contrast2012", unit: .percent),
        definition(.highlights, tag: "Highlights2012", unit: .percent),
        definition(.shadows, tag: "Shadows2012", unit: .percent),
        definition(.whites, tag: "Whites2012", unit: .percent),
        definition(.blacks, tag: "Blacks2012", unit: .percent),
        definition(.temperature, tag: "Temperature", unit: .temperatureKelvin),
        definition(.tint, tag: "Tint", unit: .tint),
        definition(.vibrance, tag: "Vibrance", unit: .percent),
        definition(.saturation, tag: "Saturation", unit: .percent),
        definition(.texture, tag: "Texture", unit: .percent),
        definition(.clarity, tag: "Clarity2012", unit: .percent),
        definition(.dehaze, tag: "Dehaze", unit: .percent),
        definition(.parametricShadows, tag: "ParametricShadows", unit: .percent),
        definition(.parametricDarks, tag: "ParametricDarks", unit: .percent),
        definition(.parametricLights, tag: "ParametricLights", unit: .percent),
        definition(.parametricHighlights, tag: "ParametricHighlights", unit: .percent),
        definition(.parametricShadowSplit, tag: "ParametricShadowSplit", unit: .dimensionless),
        definition(.parametricMidtoneSplit, tag: "ParametricMidtoneSplit", unit: .dimensionless),
        definition(.parametricHighlightSplit, tag: "ParametricHighlightSplit", unit: .dimensionless),
        definition(.sharpness, tag: "Sharpness", unit: .percent),
        definition(.sharpenRadius, tag: "SharpenRadius", unit: .dimensionless),
        definition(.sharpenDetail, tag: "SharpenDetail", unit: .percent),
        definition(.sharpenEdgeMasking, tag: "SharpenEdgeMasking", unit: .percent),
        definition(.luminanceSmoothing, tag: "LuminanceSmoothing", unit: .percent),
        definition(.luminanceNoiseReductionDetail, tag: "LuminanceNoiseReductionDetail", unit: .percent),
        definition(.luminanceNoiseReductionContrast, tag: "LuminanceNoiseReductionContrast", unit: .percent),
        definition(.colorNoiseReduction, tag: "ColorNoiseReduction", unit: .percent),
        definition(.colorNoiseReductionDetail, tag: "ColorNoiseReductionDetail", unit: .percent),
        definition(.colorNoiseReductionSmoothness, tag: "ColorNoiseReductionSmoothness", unit: .percent),
        definition(.hueAdjustmentRed, tag: "HueAdjustmentRed", unit: .dimensionless),
        definition(.hueAdjustmentOrange, tag: "HueAdjustmentOrange", unit: .dimensionless),
        definition(.hueAdjustmentYellow, tag: "HueAdjustmentYellow", unit: .dimensionless),
        definition(.hueAdjustmentGreen, tag: "HueAdjustmentGreen", unit: .dimensionless),
        definition(.hueAdjustmentAqua, tag: "HueAdjustmentAqua", unit: .dimensionless),
        definition(.hueAdjustmentBlue, tag: "HueAdjustmentBlue", unit: .dimensionless),
        definition(.hueAdjustmentPurple, tag: "HueAdjustmentPurple", unit: .dimensionless),
        definition(.hueAdjustmentMagenta, tag: "HueAdjustmentMagenta", unit: .dimensionless),
        definition(.saturationAdjustmentRed, tag: "SaturationAdjustmentRed", unit: .percent),
        definition(.saturationAdjustmentOrange, tag: "SaturationAdjustmentOrange", unit: .percent),
        definition(.saturationAdjustmentYellow, tag: "SaturationAdjustmentYellow", unit: .percent),
        definition(.saturationAdjustmentGreen, tag: "SaturationAdjustmentGreen", unit: .percent),
        definition(.saturationAdjustmentAqua, tag: "SaturationAdjustmentAqua", unit: .percent),
        definition(.saturationAdjustmentBlue, tag: "SaturationAdjustmentBlue", unit: .percent),
        definition(.saturationAdjustmentPurple, tag: "SaturationAdjustmentPurple", unit: .percent),
        definition(.saturationAdjustmentMagenta, tag: "SaturationAdjustmentMagenta", unit: .percent),
        definition(.luminanceAdjustmentRed, tag: "LuminanceAdjustmentRed", unit: .percent),
        definition(.luminanceAdjustmentOrange, tag: "LuminanceAdjustmentOrange", unit: .percent),
        definition(.luminanceAdjustmentYellow, tag: "LuminanceAdjustmentYellow", unit: .percent),
        definition(.luminanceAdjustmentGreen, tag: "LuminanceAdjustmentGreen", unit: .percent),
        definition(.luminanceAdjustmentAqua, tag: "LuminanceAdjustmentAqua", unit: .percent),
        definition(.luminanceAdjustmentBlue, tag: "LuminanceAdjustmentBlue", unit: .percent),
        definition(.luminanceAdjustmentPurple, tag: "LuminanceAdjustmentPurple", unit: .percent),
        definition(.luminanceAdjustmentMagenta, tag: "LuminanceAdjustmentMagenta", unit: .percent),
        definition(.splitToningShadowHue, tag: "SplitToningShadowHue", unit: .dimensionless),
        definition(.splitToningShadowSaturation, tag: "SplitToningShadowSaturation", unit: .percent),
        definition(.splitToningHighlightHue, tag: "SplitToningHighlightHue", unit: .dimensionless),
        definition(.splitToningHighlightSaturation, tag: "SplitToningHighlightSaturation", unit: .percent),
        definition(.splitToningBalance, tag: "SplitToningBalance", unit: .percent),
        definition(.colorGradeMidtoneHue, tag: "ColorGradeMidtoneHue", unit: .dimensionless),
        definition(.colorGradeMidtoneSat, tag: "ColorGradeMidtoneSat", unit: .percent),
        definition(.colorGradeShadowLum, tag: "ColorGradeShadowLum", unit: .percent),
        definition(.colorGradeMidtoneLum, tag: "ColorGradeMidtoneLum", unit: .percent),
        definition(.colorGradeHighlightLum, tag: "ColorGradeHighlightLum", unit: .percent),
        definition(.colorGradeBlending, tag: "ColorGradeBlending", unit: .percent),
        definition(.colorGradeGlobalHue, tag: "ColorGradeGlobalHue", unit: .dimensionless),
        definition(.colorGradeGlobalSat, tag: "ColorGradeGlobalSat", unit: .percent),
        definition(.colorGradeGlobalLum, tag: "ColorGradeGlobalLum", unit: .percent),
        definition(.autoLateralCA, tag: "AutoLateralCA", unit: .dimensionless, interpolation: .hold),
        definition(.defringePurpleAmount, tag: "DefringePurpleAmount", unit: .percent),
        definition(.defringePurpleHueLo, tag: "DefringePurpleHueLo", unit: .dimensionless),
        definition(.defringePurpleHueHi, tag: "DefringePurpleHueHi", unit: .dimensionless),
        definition(.defringeGreenAmount, tag: "DefringeGreenAmount", unit: .percent),
        definition(.defringeGreenHueLo, tag: "DefringeGreenHueLo", unit: .dimensionless),
        definition(.defringeGreenHueHi, tag: "DefringeGreenHueHi", unit: .dimensionless),
        definition(.grainAmount, tag: "GrainAmount", unit: .percent),
        definition(.glow, tag: "Glow", unit: .percent),
        definition(.redHue, tag: "RedHue", unit: .dimensionless),
        definition(.redSaturation, tag: "RedSaturation", unit: .percent),
        definition(.greenHue, tag: "GreenHue", unit: .dimensionless),
        definition(.greenSaturation, tag: "GreenSaturation", unit: .percent),
        definition(.blueHue, tag: "BlueHue", unit: .dimensionless),
        definition(.blueSaturation, tag: "BlueSaturation", unit: .percent)
    ]

    /// Non-numeric white-balance mode tag written as Custom when temperature or tint is updated.
    public static let whiteBalanceModeTag = "WhiteBalance"

    private static func definition(
        _ parameter: DevelopmentParameter,
        tag: String,
        unit: ParameterUnit,
        interpolation: ParameterInterpolation = .smoothstep
    ) -> ParameterDefinition {
        ParameterDefinition(
            parameter: parameter,
            namespaceURI: cameraRawSettingsNamespace,
            xmpTag: tag,
            unit: unit,
            interpolation: interpolation,
            validRange: nil,
            writable: true,
            compatibilityNotes: "Experimental mapping from the supplied sample or user-requested field list; range and Lightroom read-back are not certified."
        )
    }
}