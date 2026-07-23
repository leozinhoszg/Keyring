import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Credenciais de assinatura
//
// Vêm de `android/key.properties` (máquina local) ou de variáveis de ambiente
// (CI). Nenhuma das duas é versionada — veja .gitignore e docs/RELEASE.md.
//
// Por que isso importa num app de cofre: um APK assinado com a chave de debug
// recebe uma chave NOVA a cada build em runner limpo, então a atualização por
// cima falha e a única saída vira desinstalar — o que apaga o vault.db.
// ---------------------------------------------------------------------------
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingSetting(propertyKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propertyKey) ?: System.getenv(envKey)

val ksStoreFile = signingSetting("storeFile", "KEYRING_KEYSTORE_PATH")
val ksStorePassword = signingSetting("storePassword", "KEYRING_KEYSTORE_PASSWORD")
val ksKeyAlias = signingSetting("keyAlias", "KEYRING_KEY_ALIAS")
val ksKeyPassword = signingSetting("keyPassword", "KEYRING_KEY_PASSWORD")

val hasReleaseSigning =
    ksStoreFile != null && ksStorePassword != null && ksKeyAlias != null && ksKeyPassword != null

val isReleaseBuild = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
val isCi = System.getenv("CI") != null

android {
    namespace = "com.proma.keyring"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.proma.keyring"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(ksStoreFile!!)
                storePassword = ksStorePassword
                keyAlias = ksKeyAlias
                keyPassword = ksKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Sem chave configurada: no CI isso é erro (o APK publicado seria
                // inatualizável); localmente cai para debug, para não travar o
                // `flutter run --release` do dia a dia.
                if (isCi && isReleaseBuild) {
                    throw GradleException(
                        "Build de release sem chave de assinatura. Configure os secrets " +
                        "ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS " +
                        "e ANDROID_KEY_PASSWORD no repositório. Passo a passo em docs/RELEASE.md."
                    )
                }
                logger.warn(
                    "AVISO: APK de release assinado com a chave de DEBUG. Serve para teste " +
                    "local, mas não distribua — atualizações por cima vão falhar. Veja docs/RELEASE.md."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
