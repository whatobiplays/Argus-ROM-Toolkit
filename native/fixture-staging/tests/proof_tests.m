#import <Foundation/Foundation.h>
#import "../proof/AQProofActor.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int proofFailures;

#define PROOF_CHECK(value) do { \
    if (!(value)) { \
        fprintf(stderr, "proof FAIL %s:%d: %s\n", __func__, __LINE__, #value); \
        proofFailures++; \
    } \
} while (0)

typedef struct {
    const char *operation;
    const char *syscallName;
    const char *sourceName;
    const char *destinationName;
} AQProofTestCase;

static const AQProofTestCase AQProofTestCases[] = {
    {"renameat", "renameat", "rename-source", "rename-destination"},
    {"renameatx_np", "renameatx_np", "swap-left", "swap-right"},
    {"linkat", "linkat", "link-source", "link-destination"},
    {"symlinkat", "symlinkat", NULL, "symlink-link"},
    {"unlinkat", "unlinkat", NULL, "unlink-entry"},
    {"rmdir", "unlinkat", NULL, "remove-directory"}
};

static BOOL AQProofWriteFile(int directoryFD, const char *name, const char *contents) {
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

static NSString *AQProofReadFile(int directoryFD, const char *name) {
    int descriptor = openat(directoryFD, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) return nil;
    char bytes[64] = {0};
    ssize_t length = read(descriptor, bytes, sizeof(bytes) - 1);
    int savedErrno = errno;
    BOOL closed = close(descriptor) == 0;
    errno = savedErrno;
    if (length < 0 || !closed) return nil;
    return [[NSString alloc] initWithBytes:bytes
                                    length:(NSUInteger)length
                                  encoding:NSUTF8StringEncoding];
}

static BOOL AQProofPrepareCase(int directoryFD, const AQProofTestCase *testCase) {
    if (strcmp(testCase->operation, "renameat") == 0) {
        return AQProofWriteFile(directoryFD, testCase->sourceName, "source") &&
            AQProofWriteFile(directoryFD, testCase->destinationName, "destination");
    }
    if (strcmp(testCase->operation, "renameatx_np") == 0) {
        return AQProofWriteFile(directoryFD, testCase->sourceName, "left") &&
            AQProofWriteFile(directoryFD, testCase->destinationName, "right");
    }
    if (strcmp(testCase->operation, "linkat") == 0) {
        return AQProofWriteFile(directoryFD, testCase->sourceName, "linked");
    }
    if (strcmp(testCase->operation, "symlinkat") == 0) return YES;
    if (strcmp(testCase->operation, "unlinkat") == 0) {
        return AQProofWriteFile(directoryFD, testCase->destinationName, "remove");
    }
    if (strcmp(testCase->operation, "rmdir") == 0) {
        return mkdirat(directoryFD, testCase->destinationName, 0700) == 0;
    }
    return NO;
}

static void AQProofCleanupCase(int directoryFD, const AQProofTestCase *testCase) {
    if (strcmp(testCase->operation, "renameat") == 0 ||
        strcmp(testCase->operation, "renameatx_np") == 0) {
        (void)unlinkat(directoryFD, testCase->sourceName, 0);
        (void)unlinkat(directoryFD, testCase->destinationName, 0);
    } else if (strcmp(testCase->operation, "linkat") == 0) {
        (void)unlinkat(directoryFD, testCase->sourceName, 0);
        (void)unlinkat(directoryFD, testCase->destinationName, 0);
    } else if (strcmp(testCase->operation, "symlinkat") == 0) {
        (void)unlinkat(directoryFD, testCase->destinationName, 0);
    } else if (strcmp(testCase->operation, "unlinkat") == 0) {
        (void)unlinkat(directoryFD, testCase->destinationName, 0);
    } else if (strcmp(testCase->operation, "rmdir") == 0) {
        (void)unlinkat(directoryFD, testCase->destinationName, AT_REMOVEDIR);
    }
}

static int AQProofOpenTemporaryDirectory(char path[PATH_MAX]) {
    strlcpy(path, "/tmp/argus-proof-test.XXXXXX", PATH_MAX);
    if (mkdtemp(path) == NULL) return -1;
    int descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) (void)rmdir(path);
    return descriptor;
}

static void AQProofTestSuccessfulOperations(void) {
    for (NSUInteger index = 0;
         index < sizeof(AQProofTestCases) / sizeof(AQProofTestCases[0]);
         ++index) {
        const AQProofTestCase *testCase = &AQProofTestCases[index];
        char directoryPath[PATH_MAX] = {0};
        int directoryFD = AQProofOpenTemporaryDirectory(directoryPath);
        PROOF_CHECK(directoryFD >= 0);
        if (directoryFD < 0) continue;
        PROOF_CHECK(AQProofPrepareCase(directoryFD, testCase));

        NSDictionary *result = AQProofActorPerformOperation(
            directoryFD, [NSString stringWithUTF8String:testCase->operation]);
        PROOF_CHECK([result[@"status"] isEqual:@"SYSCALL_SUCCEEDED"]);
        PROOF_CHECK([result[@"operation"] isEqual:
            [NSString stringWithUTF8String:testCase->operation]]);
        PROOF_CHECK([result[@"syscall"] isEqual:
            [NSString stringWithUTF8String:testCase->syscallName]]);
        PROOF_CHECK([result[@"result"] intValue] == 0);
        PROOF_CHECK([result[@"errno"] intValue] == 0);
        PROOF_CHECK([result[@"effective_uid"] unsignedIntValue] == geteuid());

        if (strcmp(testCase->operation, "renameat") == 0) {
            PROOF_CHECK(AQProofReadFile(directoryFD, testCase->sourceName) == nil);
            PROOF_CHECK([AQProofReadFile(directoryFD, testCase->destinationName)
                isEqual:@"source"]);
        } else if (strcmp(testCase->operation, "renameatx_np") == 0) {
            PROOF_CHECK([AQProofReadFile(directoryFD, testCase->sourceName) isEqual:@"right"]);
            PROOF_CHECK([AQProofReadFile(directoryFD, testCase->destinationName) isEqual:@"left"]);
        } else if (strcmp(testCase->operation, "linkat") == 0) {
            struct stat sourceInfo = {0};
            struct stat destinationInfo = {0};
            PROOF_CHECK(fstatat(directoryFD, testCase->sourceName, &sourceInfo,
                                AT_SYMLINK_NOFOLLOW) == 0);
            PROOF_CHECK(fstatat(directoryFD, testCase->destinationName, &destinationInfo,
                                AT_SYMLINK_NOFOLLOW) == 0);
            PROOF_CHECK(sourceInfo.st_dev == destinationInfo.st_dev &&
                        sourceInfo.st_ino == destinationInfo.st_ino);
        } else if (strcmp(testCase->operation, "symlinkat") == 0) {
            char target[64] = {0};
            ssize_t length = readlinkat(directoryFD, testCase->destinationName,
                                        target, sizeof(target) - 1);
            PROOF_CHECK(length == (ssize_t)strlen("symlink-destination"));
            PROOF_CHECK(strcmp(target, "symlink-destination") == 0);
        } else if (strcmp(testCase->operation, "unlinkat") == 0) {
            struct stat info = {0};
            PROOF_CHECK(fstatat(directoryFD, testCase->destinationName, &info,
                                AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT);
        } else if (strcmp(testCase->operation, "rmdir") == 0) {
            struct stat info = {0};
            PROOF_CHECK(fstatat(directoryFD, testCase->destinationName, &info,
                                AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT);
        }

        (void)fchmod(directoryFD, 0700);
        AQProofCleanupCase(directoryFD, testCase);
        (void)close(directoryFD);
        PROOF_CHECK(rmdir(directoryPath) == 0);
    }
}

static void AQProofTestPermissionDenials(void) {
    if (geteuid() == 0) {
        fprintf(stderr, "proof FAIL %s:%d: permission tests must not run as root\n",
                __func__, __LINE__);
        proofFailures++;
        return;
    }

    for (NSUInteger index = 0;
         index < sizeof(AQProofTestCases) / sizeof(AQProofTestCases[0]);
         ++index) {
        const AQProofTestCase *testCase = &AQProofTestCases[index];
        char directoryPath[PATH_MAX] = {0};
        int directoryFD = AQProofOpenTemporaryDirectory(directoryPath);
        PROOF_CHECK(directoryFD >= 0);
        if (directoryFD < 0) continue;
        PROOF_CHECK(AQProofPrepareCase(directoryFD, testCase));
        PROOF_CHECK(fchmod(directoryFD, 0000) == 0);

        NSDictionary *result = AQProofActorPerformOperation(
            directoryFD, [NSString stringWithUTF8String:testCase->operation]);
        PROOF_CHECK([result[@"status"] isEqual:@"SYSCALL_FAILED"]);
        PROOF_CHECK([result[@"result"] intValue] == -1);
        int operationErrno = [result[@"errno"] intValue];
        PROOF_CHECK(operationErrno == EACCES || operationErrno == EPERM);

        PROOF_CHECK(fchmod(directoryFD, 0700) == 0);
        if (strcmp(testCase->operation, "renameat") == 0) {
            PROOF_CHECK([AQProofReadFile(directoryFD, testCase->sourceName) isEqual:@"source"]);
            PROOF_CHECK([AQProofReadFile(directoryFD, testCase->destinationName)
                isEqual:@"destination"]);
        } else if (strcmp(testCase->operation, "renameatx_np") == 0) {
            PROOF_CHECK([AQProofReadFile(directoryFD, testCase->sourceName) isEqual:@"left"]);
            PROOF_CHECK([AQProofReadFile(directoryFD, testCase->destinationName)
                isEqual:@"right"]);
        } else if (strcmp(testCase->operation, "linkat") == 0) {
            struct stat info = {0};
            PROOF_CHECK(fstatat(directoryFD, testCase->destinationName, &info,
                                AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT);
        } else if (strcmp(testCase->operation, "symlinkat") == 0) {
            struct stat info = {0};
            PROOF_CHECK(fstatat(directoryFD, testCase->destinationName, &info,
                                AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT);
        } else if (strcmp(testCase->operation, "unlinkat") == 0) {
            PROOF_CHECK([AQProofReadFile(directoryFD, testCase->destinationName)
                isEqual:@"remove"]);
        } else if (strcmp(testCase->operation, "rmdir") == 0) {
            struct stat info = {0};
            PROOF_CHECK(fstatat(directoryFD, testCase->destinationName, &info,
                                AT_SYMLINK_NOFOLLOW) == 0 && S_ISDIR(info.st_mode));
        }

        AQProofCleanupCase(directoryFD, testCase);
        (void)close(directoryFD);
        PROOF_CHECK(rmdir(directoryPath) == 0);
    }
}

static void AQProofTestRejectsUncontrolledInputs(void) {
    char directoryPath[PATH_MAX] = {0};
    int directoryFD = AQProofOpenTemporaryDirectory(directoryPath);
    PROOF_CHECK(directoryFD >= 0);
    if (directoryFD < 0) return;

    PROOF_CHECK(AQProofActorPerformOperation(-1, @"unlinkat") == nil);
    PROOF_CHECK(AQProofActorPerformOperation(directoryFD, @"") == nil);
    PROOF_CHECK(AQProofActorPerformOperation(directoryFD, nil) == nil);
    PROOF_CHECK(AQProofActorPerformOperation(directoryFD, @"../../etc/passwd") == nil);

    int regularFD = openat(directoryFD, "regular-file",
                           O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    PROOF_CHECK(regularFD >= 0);
    if (regularFD >= 0) {
        PROOF_CHECK(AQProofActorPerformOperation(regularFD, @"unlinkat") == nil);
        (void)close(regularFD);
    }

    (void)unlinkat(directoryFD, "regular-file", 0);
    (void)close(directoryFD);
    PROOF_CHECK(rmdir(directoryPath) == 0);
}

int main(void) {
    if (geteuid() == 0) {
        fprintf(stderr, "proof FAIL: synthetic permission checks must run unprivileged\n");
        return 1;
    }
    NSDictionary *syntheticReport = AQProofActorRunSyntheticSuite();
    PROOF_CHECK([syntheticReport[@"status"] isEqual:@"SYNTHETIC_PASS"]);
    PROOF_CHECK([syntheticReport[@"classification"] isEqual:@"SYNTHETIC_ONLY"]);
    PROOF_CHECK([syntheticReport[@"operations"] count] ==
        sizeof(AQProofTestCases) / sizeof(AQProofTestCases[0]));
    PROOF_CHECK([syntheticReport[@"permission_denials"] count] == 1);
    AQProofTestSuccessfulOperations();
    AQProofTestPermissionDenials();
    AQProofTestRejectsUncontrolledInputs();
    if (proofFailures != 0) {
        fprintf(stderr, "proof tests: %d failure(s)\n", proofFailures);
        return 1;
    }
    printf("proof tests: 0 failure(s); synthetic filesystem syscalls only\n");
    return 0;
}
