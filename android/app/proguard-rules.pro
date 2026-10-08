# kotlinx.serialization writes its own serializers as generated code; R8 has to be told the
# names it looks up at runtime survive shrinking.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.sahilchanna.habits.** {
    *** Companion;
}
-keepclasseswithmembers class com.sahilchanna.habits.** {
    kotlinx.serialization.KSerializer serializer(...);
}
