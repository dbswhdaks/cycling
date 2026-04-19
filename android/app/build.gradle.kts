import java.util.Properties
import java.io.FileInputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.util.Locale
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val env = System.getenv()
fun envOrProperty(envKey: String, propertyKey: String): String? {
    val envValue = env[envKey]?.trim().orEmpty()
    if (envValue.isNotEmpty()) {
        return envValue
    }

    val propertyValue = (keystoreProperties[propertyKey] as String?)?.trim().orEmpty()
    if (propertyValue.isNotEmpty()) {
        return propertyValue
    }

    return null
}

fun normalizeSha1(value: String): String {
    return value.replace(":", "").replace("-", "").uppercase(Locale.US)
}

val releaseStoreFilePath = envOrProperty("ANDROID_UPLOAD_STORE_FILE", "storeFile")
val releaseStorePassword = envOrProperty("ANDROID_UPLOAD_STORE_PASSWORD", "storePassword")
val releaseKeyAlias = envOrProperty("ANDROID_UPLOAD_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = envOrProperty("ANDROID_UPLOAD_KEY_PASSWORD", "keyPassword")

val expectedUploadSha1 = (
    envOrProperty("ANDROID_UPLOAD_SHA1", "expectedSha1")
        ?: "CD:95:22:8D:BB:BF:EB:60:25:91:DE:00:36:87:8A:64:B1:32:66:86"
).uppercase(Locale.US)

val releaseStoreFile = releaseStoreFilePath?.let { file(it) }
val hasReleaseSigning = releaseStoreFile != null &&
    releaseStoreFile.exists() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

val releaseTaskRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true) ||
        taskName.contains("bundle", ignoreCase = true) ||
        taskName.contains("publish", ignoreCase = true)
}

if (releaseTaskRequested && !hasReleaseSigning) {
    throw GradleException(
        "Release signing is not fully configured. Set ANDROID_UPLOAD_* environment variables " +
            "or provide android/key.properties with valid storeFile/storePassword/keyAlias/keyPassword."
    )
}

if (releaseTaskRequested && hasReleaseSigning) {
    val certificateSha1 = FileInputStream(releaseStoreFile).use { inputStream ->
        val keyStore = KeyStore.getInstance(KeyStore.getDefaultType())
        keyStore.load(inputStream, releaseStorePassword!!.toCharArray())

        val certificate = keyStore.getCertificate(releaseKeyAlias)
            ?: throw GradleException("Keystore alias '$releaseKeyAlias' was not found.")
        val x509 = certificate as? X509Certificate
            ?: throw GradleException("Certificate for alias '$releaseKeyAlias' is not an X509 certificate.")

        MessageDigest.getInstance("SHA-1")
            .digest(x509.encoded)
            .joinToString(":") { byte -> "%02X".format(byte) }
    }

    if (normalizeSha1(certificateSha1) != normalizeSha1(expectedUploadSha1)) {
        throw GradleException(
            "Wrong upload keystore detected. Expected SHA1: $expectedUploadSha1, " +
                "but found: $certificateSha1. Use the correct upload keystore before building release."
        )
    }
}

android {
    namespace = "com.gyeongryunplus.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.gyeongryunplus.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = releaseKeyAlias ?: ""
            keyPassword = releaseKeyPassword ?: ""
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword ?: ""
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
