import Foundation

/// Drop-in clone of Apple's `@Generable` macro. Apply it to a `struct` (or
/// `class`) of `Codable & Sendable` stored properties and it synthesizes
/// the `static var generationSchema: GenerationSchema` your `Generable`
/// conformance needs.
///
/// ```swift
/// @Generable
/// struct WeatherReport {
///     @Guide(description: "City name")
///     let city: String
///     let temperatureCelsius: Double
///     let conditions: String
/// }
/// ```
///
/// Behavior matches Apple's framework:
///
/// - Field optionality (`T?`) drops the field out of `required`.
/// - `@Guide(description:)` annotations on stored properties set per-field
///   schema descriptions.
/// - Nested `@Generable` types are referenced by their generated
///   `generationSchema`, so the schema composes recursively.
/// - Arrays of primitives or `@Generable` types are supported via Swift's
///   `[T]` sugar.
@attached(member, names: named(generationSchema))
@attached(extension, conformances: PrivateFoundationModels.Generable)
public macro Generable(description: String? = nil) =
    #externalMacro(module: "PFMMacros", type: "GenerableMacro")

/// Apply per-property descriptions that flow into the generated schema.
/// Reads from `@Generable`'s expansion — has no runtime effect on its own.
///
/// ```swift
/// @Generable
/// struct Recipe {
///     @Guide(description: "The dish's display name.")
///     let name: String
/// }
/// ```
@attached(peer)
public macro Guide(description: String) =
    #externalMacro(module: "PFMMacros", type: "GuideMacro")
