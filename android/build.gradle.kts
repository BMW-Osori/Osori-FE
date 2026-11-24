allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
// universal_ble 은 AGP 9 내장 Kotlin 을 전제함. AGP 8 에서는 Kotlin 플러그인을 직접 붙임 (AGP 9 로 올리면 삭제)
subprojects {
    if (name == "universal_ble") {
        pluginManager.withPlugin("com.android.library") { pluginManager.apply("org.jetbrains.kotlin.android") }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
