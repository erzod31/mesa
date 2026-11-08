package com.mesa.mesa
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdatePolicyTest {
    private val current = UpdateIdentity("com.mesa.mesa", 34, "1.17.0", setOf("family-certificate"), 24)
    private val valid = current.copy(code=35, version="1.18.0")
    private fun rejected(archive: UpdateIdentity, code: Long=35, version: String="1.18.0", sdk: Int=36) {
        var failed = false
        try { UpdatePolicy.verify(current, archive, code, version, sdk) } catch (_: IllegalArgumentException) { failed=true }
        assertTrue(failed)
    }
    @Test fun acceptsSameProductAndCertificate() { UpdatePolicy.verify(current,valid,35,"1.18.0",36) }
    @Test fun rejectsAnotherProduct() { rejected(valid.copy(packageName="another.app")) }
    @Test fun rejectsCertificateMismatch() { rejected(valid.copy(signers=setOf("foreign"))) }
    @Test fun rejectsMissingCertificate() { rejected(valid.copy(signers=emptySet())) }
    @Test fun rejectsWrongCode() { rejected(valid.copy(code=36)) }
    @Test fun rejectsSameCode() { rejected(valid.copy(code=34),34) }
    @Test fun rejectsDowngradeEvenWithHigherCode() { rejected(valid.copy(version="1.0.0"),35,"1.0.0") }
    @Test fun rejectsWrongVersionName() { rejected(valid.copy(version="1.19.0")) }
    @Test fun rejectsIncompatibleAndroid() { rejected(valid.copy(minSdk=37)) }
}
