plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.0.21" apply false
    // Room's annotation processor. KSP rather than kapt: the schema is generated, not
    // reflected, and kapt would run a second full Kotlin compile for it.
    id("com.google.devtools.ksp") version "2.0.21-1.0.25" apply false
}
