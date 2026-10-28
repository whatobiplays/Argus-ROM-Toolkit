#import <Foundation/Foundation.h>

static int AQProofActorBlocked(const char *code) {
    fprintf(stderr, "{\"status\":\"BLOCKED\",\"code\":\"%s\"}\n", code);
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-check") == 0) {
            return AQProofActorBlocked("PROOF_NAMESPACE_NOT_INSTALLED");
        }
        if (argc != 3 || strcmp(argv[1], "--case") != 0) {
            return AQProofActorBlocked("USAGE");
        }
        static const char *const allowed[] = {
            "namespace", "ipc", "source", "export", "crash", "recovery", "cleanup"
        };
        BOOL known = NO;
        for (NSUInteger index = 0; index < sizeof(allowed) / sizeof(allowed[0]); ++index) {
            known = known || strcmp(argv[2], allowed[index]) == 0;
        }
        if (!known) return AQProofActorBlocked("CASE_UNSUPPORTED");
        return AQProofActorBlocked("KERNEL_ISOLATION_AUTHORITY_UNAVAILABLE");
    }
}
