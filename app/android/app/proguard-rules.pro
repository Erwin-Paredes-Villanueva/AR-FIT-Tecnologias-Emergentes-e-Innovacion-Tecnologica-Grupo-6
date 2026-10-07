# WorkManager crea su base de datos Room por reflexión (WorkDatabase_Impl);
# sin estas reglas R8 la elimina y la app se cierra al arrancar.
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.room.** { *; }
-dontwarn androidx.work.**
