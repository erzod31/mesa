package com.mesa.mesa

/** Pure policy shared by the real PackageManager adapter and JVM tests. */
data class UpdateIdentity(val packageName: String, val code: Long, val version: String,
                          val signers: Set<String>, val minSdk: Int)

object UpdatePolicy {
    fun verify(current: UpdateIdentity, archive: UpdateIdentity, expectedCode: Long,
               expectedVersion: String, sdk: Int) {
        require(archive.packageName == current.packageName && current.packageName == "com.mesa.mesa") { "La APK no pertenece a Mesa." }
        require(archive.code == expectedCode && expectedCode > current.code) { "No es una versión más nueva de Mesa." }
        require(archive.version == expectedVersion && expectedVersion.matches(Regex("\\d+\\.\\d+\\.\\d+"))) { "La versión de la APK no coincide con el canal." }
        val next = expectedVersion.split('.').map { it.toLong() }
        val previous = current.version.split('.').map { it.toLongOrNull() ?: -1L }
        require(previous.size == 3 && previous.all { it >= 0 }) { "No se pudo comprobar la versión instalada." }
        val firstDifference = next.indices.firstOrNull { next[it] != previous[it] }
        require(firstDifference == null || next[firstDifference] > previous[firstDifference]) { "No se permite retroceder de versión." }
        require(current.signers.isNotEmpty() && current.signers == archive.signers) { "La firma de la APK no coincide con Mesa. No se instalará." }
        require(archive.minSdk <= sdk) { "Esta actualización requiere un Android más reciente." }
    }
}
