#import <Foundation/Foundation.h>
#import "AQProofActor.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/stat.h>
#include <unistd.h>

NSDictionary<NSString *, id> *AQProofActorPerformOperation(int directoryFD,
                                                            NSString *operation) {
    if (directoryFD < 0 || operation.length == 0) return nil;

    struct stat directoryInfo = {0};
    if (fstat(directoryFD, &directoryInfo) != 0 || !S_ISDIR(directoryInfo.st_mode)) return nil;

    const char *operationName = operation.UTF8String;
    if (operationName == NULL) return nil;
    const char *syscallName = NULL;
    int result = -1;
    errno = 0;

    if (strcmp(operationName, "renameat") == 0) {
        syscallName = "renameat";
        result = renameat(directoryFD, "rename-source",
                          directoryFD, "rename-destination");
    } else if (strcmp(operationName, "renameatx_np") == 0) {
        syscallName = "renameatx_np";
        result = renameatx_np(directoryFD, "swap-left",
                              directoryFD, "swap-right", RENAME_SWAP);
    } else if (strcmp(operationName, "linkat") == 0) {
        syscallName = "linkat";
        result = linkat(directoryFD, "link-source",
                        directoryFD, "link-destination", 0);
    } else if (strcmp(operationName, "symlinkat") == 0) {
        syscallName = "symlinkat";
        result = symlinkat("symlink-destination", directoryFD, "symlink-link");
    } else if (strcmp(operationName, "unlinkat") == 0) {
        syscallName = "unlinkat";
        result = unlinkat(directoryFD, "unlink-entry", 0);
    } else if (strcmp(operationName, "rmdir") == 0) {
        syscallName = "unlinkat";
        result = unlinkat(directoryFD, "remove-directory", AT_REMOVEDIR);
    } else {
        return nil;
    }

    int syscallErrno = result == 0 ? 0 : errno;
    NSString *syscall = [NSString stringWithFormat:@"%s", syscallName];
    return @{
        @"status": result == 0 ? @"SYSCALL_SUCCEEDED" : @"SYSCALL_FAILED",
        @"operation": operation,
        @"syscall": syscall,
        @"result": @(result),
        @"errno": @(syscallErrno),
        @"effective_uid": @(geteuid())
    };
}

static BOOL AQProofActorWriteFixture(int directoryFD, const char *name,
                                     const char *contents) {
    int descriptor = openat(directoryFD, name,
                            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (descriptor < 0) return NO;
    size_t remaining = strlen(contents);
    const char *cursor = contents;
    while (remaining > 0) {
        ssize_t written = write(descriptor, cursor, remaining);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) {
            (void)close(descriptor);
            return NO;
        }
        cursor += written;
        remaining -= (size_t)written;
    }
    return close(descriptor) == 0;
}

static void AQProofActorRemoveSyntheticEntries(int directoryFD) {
    static const char *const files[] = {
        "rename-source", "rename-destination", "swap-left", "swap-right",
        "link-source", "link-destination", "symlink-link", "unlink-entry"
    };
    for (NSUInteger index = 0; index < sizeof(files) / sizeof(files[0]); ++index) {
        (void)unlinkat(directoryFD, files[index], 0);
    }
    (void)unlinkat(directoryFD, "remove-directory", AT_REMOVEDIR);
}

NSDictionary<NSString *, id> *AQProofActorRunSyntheticSuite(void) {
    if (geteuid() == 0) {
        return @{
            @"status": @"BLOCKED",
            @"code": @"SYNTHETIC_PROOF_REQUIRES_UNPRIVILEGED_UID",
            @"classification": @"SYNTHETIC_ONLY"
        };
    }

    NSString *temporaryTemplate = [[NSTemporaryDirectory() stringByStandardizingPath]
        stringByAppendingPathComponent:@"argus-proof-synthetic.XXXXXX"];
    char temporaryPath[PATH_MAX] = {0};
    if (![temporaryTemplate getFileSystemRepresentation:temporaryPath
                                                maxLength:sizeof(temporaryPath)] ||
        mkdtemp(temporaryPath) == NULL) {
        return @{
            @"status": @"FAIL",
            @"code": @"SYNTHETIC_DIRECTORY_CREATE_FAILED",
            @"classification": @"SYNTHETIC_ONLY"
        };
    }
    NSString *retainedPath = [NSString stringWithFormat:@"%s", temporaryPath];

    int directoryFD = open(temporaryPath,
                           O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (directoryFD < 0) {
        return @{
            @"status": @"FAIL",
            @"code": @"SYNTHETIC_DIRECTORY_OPEN_FAILED",
            @"errno": @(errno),
            @"classification": @"SYNTHETIC_ONLY",
            @"retained_directory": retainedPath
        };
    }

    struct stat directoryInfo = {0};
    int statResult = fstat(directoryFD, &directoryInfo);
    int statErrno = statResult == 0 ? 0 : errno;
    BOOL directoryTrusted = statResult == 0 &&
        S_ISDIR(directoryInfo.st_mode) && directoryInfo.st_uid == geteuid() &&
        (directoryInfo.st_mode & 0777) == 0700;
    if (!directoryTrusted) {
        /* The pathname may now refer to a replacement; retain it for review. */
        (void)close(directoryFD);
        return @{
            @"status": @"FAIL",
            @"code": @"SYNTHETIC_DIRECTORY_IDENTITY_INVALID",
            @"errno": @(statErrno),
            @"classification": @"SYNTHETIC_ONLY",
            @"retained_directory": retainedPath
        };
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *operations = [NSMutableArray array];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    BOOL fixturesCreated =
        AQProofActorWriteFixture(directoryFD, "rename-source", "source") &&
        AQProofActorWriteFixture(directoryFD, "rename-destination", "destination") &&
        AQProofActorWriteFixture(directoryFD, "swap-left", "left") &&
        AQProofActorWriteFixture(directoryFD, "swap-right", "right") &&
        AQProofActorWriteFixture(directoryFD, "link-source", "linked") &&
        AQProofActorWriteFixture(directoryFD, "unlink-entry", "remove") &&
        mkdirat(directoryFD, "remove-directory", 0700) == 0;
    if (!fixturesCreated) [failures addObject:@"SYNTHETIC_FIXTURE_SETUP_FAILED"];

    NSArray<NSString *> *operationNames = @[
        @"renameat", @"renameatx_np", @"linkat", @"symlinkat", @"unlinkat", @"rmdir"
    ];
    if (fixturesCreated) {
        for (NSString *operation in operationNames) {
            NSDictionary<NSString *, id> *result =
                AQProofActorPerformOperation(directoryFD, operation);
            if (result != nil) [operations addObject:result];
            if (![result[@"status"] isEqual:@"SYSCALL_SUCCEEDED"]) {
                [failures addObject:[NSString stringWithFormat:@"SYSCALL_FAILED:%@", operation]];
            }
        }
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *permissionDenials = [NSMutableArray array];
    BOOL denialFixtureCreated = AQProofActorWriteFixture(directoryFD, "unlink-entry", "retain");
    BOOL modeChanged = denialFixtureCreated && fchmod(directoryFD, 0000) == 0;
    NSDictionary<NSString *, id> *denial = modeChanged ?
        AQProofActorPerformOperation(directoryFD, @"unlinkat") : nil;
    int restoreResult = fchmod(directoryFD, 0700);
    if (denial != nil) [permissionDenials addObject:denial];
    int denialErrno = [denial[@"errno"] intValue];
    BOOL denialObserved = modeChanged && restoreResult == 0 &&
        [denial[@"status"] isEqual:@"SYSCALL_FAILED"] &&
        [denial[@"result"] intValue] == -1 &&
        (denialErrno == EACCES || denialErrno == EPERM);
    if (!denialObserved) [failures addObject:@"KERNEL_PERMISSION_DENIAL_NOT_OBSERVED"];

    AQProofActorRemoveSyntheticEntries(directoryFD);
    int closeResult = close(directoryFD);
    int removeResult = rmdir(temporaryPath);
    if (closeResult != 0 || removeResult != 0) {
        [failures addObject:@"SYNTHETIC_DIRECTORY_CLEANUP_FAILED"];
    }

    NSMutableDictionary<NSString *, id> *report = [@{
        @"status": failures.count == 0 ? @"SYNTHETIC_PASS" : @"FAIL",
        @"classification": @"SYNTHETIC_ONLY",
        @"scope": @"PRIVATE_TEMPORARY_DIRECTORY",
        @"effective_uid": @(geteuid()),
        @"operations": operations,
        @"permission_denials": permissionDenials,
        @"cleanup_complete": @(closeResult == 0 && removeResult == 0),
        @"failures": failures
    } mutableCopy];
    if (failures.count != 0 && removeResult != 0) {
        report[@"retained_directory"] = retainedPath;
    }
    return report;
}

static int AQProofActorBlocked(const char *code) {
    fprintf(stderr, "{\"status\":\"BLOCKED\",\"code\":\"%s\"}\n", code);
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-check") == 0) {
            return AQProofActorBlocked("PROOF_NAMESPACE_NOT_INSTALLED");
        }
        if (argc == 2 && strcmp(argv[1], "--synthetic-self-test") == 0) {
            NSDictionary *report = AQProofActorRunSyntheticSuite();
            NSError *error = nil;
            NSData *json = [NSJSONSerialization dataWithJSONObject:report
                                                          options:NSJSONWritingSortedKeys
                                                            error:&error];
            if (json == nil || error != nil) {
                return AQProofActorBlocked("SYNTHETIC_REPORT_ENCODING_FAILED");
            }
            fwrite(json.bytes, 1, json.length, stdout);
            fputc('\n', stdout);
            return [report[@"status"] isEqual:@"SYNTHETIC_PASS"] ? 0 : 2;
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
