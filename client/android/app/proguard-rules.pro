# ML Kit discovers these registrars by their manifest names and zero-argument
# constructors. R8 kept the class names but removed the constructors in release,
# leaving TranslatorImpl.Factory unavailable. OCR now runs on the private PC.
-keep class com.google.mlkit.** implements com.google.firebase.components.ComponentRegistrar {
    *;
}
