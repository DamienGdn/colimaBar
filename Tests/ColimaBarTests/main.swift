import Foundation

print("Running ColimaBar tests...\n")

test_parseListJSON_running()
test_parseListJSON_stopped()
test_parseListJSON_invalid_returnsNil()
test_memoryGB_conversion()
test_portainerExists_found()
test_portainerExists_notFound()
test_fetchStateSync_running_portainerExists()
test_fetchStateSync_running_portainerMissing()
test_fetchStateSync_stopped_skipsDockerCheck()
test_fetchStateSync_invalidJSON_returnsUnknown()
// test_colimaConfig() — activated in Task 8 (ColimaConfig not yet implemented)

print("\n\(_passed) passed, \(_failed) failed")
if _failed > 0 {
    exit(1)
}
