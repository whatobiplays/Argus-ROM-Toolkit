#import <Foundation/Foundation.h>
#import "AQProofActor.h"

#include <unistd.h>

static const char *const AQProofManifestPath =
    "/Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json";

static int AQProofBlocked(const char *code) {
    fprintf(stderr, "{\"status\":\"BLOCKED\",\"code\":\"%s\"}\n", code);
    return 2;
}

static BOOL AQProofIsInspectionCommand(const char *command) {
    return command != NULL &&
        (strcmp(command, "inspect") == 0 || strcmp(command, "verify-install") == 0 ||
         strcmp(command, "report") == 0 || strcmp(command, "verify-removal") == 0 ||
         strcmp(command, "--self-check") == 0 ||
         strcmp(command, "--synthetic-self-test") == 0);
}

static int AQProofEmitReport(NSDictionary<NSString *, id> *report) {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:report
                                                    options:NSJSONWritingSortedKeys
                                                      error:&error];
    if (json == nil || error != nil) {
        return AQProofBlocked("SYNTHETIC_REPORT_ENCODING_FAILED");
    }
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    return [report[@"status"] isEqual:@"SYNTHETIC_PASS"] ? 0 : 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return AQProofBlocked("USAGE");
        if (argc == 2 && strcmp(argv[1], "--synthetic-self-test") == 0) {
            if (geteuid() == 0) {
                return AQProofBlocked("SYNTHETIC_PROOF_REQUIRES_UNPRIVILEGED_UID");
            }
            return AQProofEmitReport(AQProofActorRunSyntheticSuite());
        }
        if (geteuid() == 0 && !AQProofIsInspectionCommand(argv[1])) {
            /* This source tree has no owner-approved signed proof manifest or
             * disposable VM authorization. A root flag is never authority. */
            return AQProofBlocked("PRIVILEGED_PROOF_EXECUTION_NOT_AUTHORIZED");
        }
        if (access(AQProofManifestPath, R_OK) != 0 || access("/Volumes/ArgusIsolationProof", R_OK) != 0) {
            return AQProofBlocked("PROOF_BUNDLE_AND_OWNER_APPROVAL_UNAVAILABLE");
        }
        /* Artifact verification and privileged setup are intentionally absent
         * until an independently reviewed bundle, pinned hashes, and disposable
         * VM are supplied through a separate owner authorization. */
        return AQProofBlocked("PROOF_IMPLEMENTATION_NOT_AUTHORIZED");
    }
}
