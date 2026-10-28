#import "../core/AQSecurity.h"
#import <Security/Security.h>

#include <fcntl.h>
#include <membership.h>
#include <sys/acl.h>
#include <sys/stat.h>
#include <unistd.h>

#if !defined(AQ_SECURITY_TESTING)
#error "The security test target must define AQ_SECURITY_TESTING."
#endif

/* These entry points are compiled only into the disposable test target. They
 * exercise pure predicates and test-only policy provenance. They cannot create
 * production trust because the production build does not define this macro. */
extern BOOL AQSecurityTestTrustPolicy(AQInstallationPolicy *policy);
extern BOOL AQSecurityTestEvaluatePeerCodeFacts(NSDictionary *info,
    AQInstallationPolicy *policy, AQPeerRole role, NSError **error);
extern BOOL AQSecurityTestCopyPeerExecutablePath(NSDictionary *info, NSString **path, NSError **error);
extern BOOL AQSecurityTestEvaluateOwnerKeyAttributes(NSDictionary *attributes,
    AQInstallationPolicy *policy, NSError **error);
extern BOOL AQSecurityTestValidateDirectoryFD(int fd, uid_t expectedUID,
    mode_t mode, NSError **error);
extern BOOL AQSecurityTestValidateFileFD(int fd, uid_t expectedUID,
    mode_t mode, NSError **error);
extern BOOL AQSecurityTestEvaluateNonLoginAccountFacts(NSString *password, NSString *shell);
extern BOOL AQSecurityTestMessageHasLivePeer(xpc_object_t message, NSError **error);
extern void AQSecurityTestSetAuthenticatedPeerAPIsUnavailable(BOOL unavailable);

static int failures;
static int checks;

static void Check(BOOL condition, const char *description) {
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL security: %s\n", description);
        failures++;
    }
}

static NSData *JSON(id value) {
    return [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
}

static NSData *P256Point(void) {
    const uint8_t point[] = {
        0x04,0x6b,0x17,0xd1,0xf2,0xe1,0x2c,0x42,0x47,0xf8,0xbc,0xe6,0xe5,0x63,0xa4,0x40,0xf2,
        0x77,0x03,0x7d,0x81,0x2d,0xeb,0x33,0xa0,0xf4,0xa1,0x39,0x45,0xd8,0x98,0xc2,0x96,
        0x4f,0xe3,0x42,0xe2,0xfe,0x1a,0x7f,0x9b,0x8e,0xe7,0xeb,0x4a,0x7c,0x0f,0x9e,0x16,
        0x2b,0xce,0x33,0x57,0x6b,0x31,0x5e,0xce,0xcb,0xb6,0x40,0x68,0x37,0xbf,0x51,0xf5
    };
    return [NSData dataWithBytes:point length:sizeof(point)];
}

static NSDictionary *PolicyFixtureWithPublicKey(NSData *publicKey) {
    return @{
        @"schema": @1,
        @"team_id": @"ABCDE12345",
        @"broker_cdhash": @"1111111111111111111111111111111111111111",
        @"service_cdhash": @"2222222222222222222222222222222222222222",
        @"owner_uid": @501,
        @"service_uid": @499,
        @"key_access_group": @"ABCDE12345.com.argusromtoolkit.fixture-staging.broker",
        @"key_tag": @"com.argusromtoolkit.fixture-staging.owner-consent.v1",
        @"owner_public_key": [publicKey base64EncodedStringWithOptions:0]
    };
}

static NSDictionary *PolicyFixture(void) {
    return PolicyFixtureWithPublicKey(P256Point());
}

static AQInstallationPolicy *TrustedTestPolicy(NSDictionary *fixture, NSError **error) {
    AQInstallationPolicy *policy = AQParseInstallationPolicy(JSON(fixture), error);
    if (!policy || !AQSecurityTestTrustPolicy(policy)) return nil;
    return policy;
}

static void TestPolicyParsing(void) {
    NSError *error = nil;
    AQInstallationPolicy *policy = AQParseInstallationPolicy(JSON(PolicyFixture()), &error);
    Check(policy != nil && error == nil, "valid pinned policy parses");
    Check(policy && !policy.isInstalledPolicy, "caller bytes never grant installation trust");
    Check(policy && [policy.ownerPublicKey isEqual:P256Point()], "canonical owner key survives parsing");
    Check(policy && AQSecurityTestTrustPolicy(policy), "test-only trust hook accepts a parsed fixture");
    Check(policy && policy.isInstalledPolicy, "test-only policy is visibly marked installed");
    Check(policy && AQSecurityTestTrustPolicy(nil) == NO, "nil policy cannot acquire test authority");

    NSMutableDictionary *unenrolled = [PolicyFixture() mutableCopy];
    unenrolled[@"owner_public_key"] = NSNull.null;
    AQInstallationPolicy *empty = AQParseInstallationPolicy(JSON(unenrolled), NULL);
    Check(empty != nil && empty.ownerPublicKey == nil, "explicit null key represents pre-enrollment");

    for (NSString *field in PolicyFixture()) {
        NSMutableDictionary *missing = [PolicyFixture() mutableCopy];
        [missing removeObjectForKey:field];
        Check(AQParseInstallationPolicy(JSON(missing), NULL) == nil, "missing policy field rejected");
    }

    NSArray *invalid = @[
        @[@"schema", @2], @[@"schema", @YES], @[@"schema", @"1"],
        @[@"team_id", @""], @[@"team_id", @"abcde12345"],
        @[@"team_id", @"ABCDE1234\" or true"],
        @[@"broker_cdhash", @"abcd"],
        @[@"service_cdhash", @"GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG"],
        @[@"owner_uid", @0], @[@"owner_uid", @(-1)], @[@"owner_uid", @YES],
        @[@"owner_uid", @1.5], @[@"owner_uid", @4294967295ULL],
        @[@"service_uid", @501], @[@"service_uid", @0],
        @[@"key_access_group", @"ABCDE12345.shared"],
        @[@"key_tag", @"caller-key"], @[@"owner_public_key", @"not base64!"],
        @[@"owner_public_key", @"BA=="], @[@"owner_public_key", @{}],
        @[@"production_test_mode", @YES]
    ];
    for (NSArray *change in invalid) {
        NSMutableDictionary *bad = [PolicyFixture() mutableCopy];
        bad[change[0]] = change[1];
        error = nil;
        Check(AQParseInstallationPolicy(JSON(bad), &error) == nil && error != nil,
              "invalid policy field fails closed with an error");
    }

    NSString *source = [[NSString alloc] initWithData:JSON(PolicyFixture()) encoding:NSUTF8StringEncoding];
    NSString *duplicate = [@"{\"schema\":1," stringByAppendingString:[source substringFromIndex:1]];
    Check(AQParseInstallationPolicy(
              (NSData *)[duplicate dataUsingEncoding:NSUTF8StringEncoding], NULL) == nil,
          "duplicate identical keys rejected before dictionary collapse");
    duplicate = [@"{\"sche\\u006da\":1," stringByAppendingString:[source substringFromIndex:1]];
    Check(AQParseInstallationPolicy(
              (NSData *)[duplicate dataUsingEncoding:NSUTF8StringEncoding], NULL) == nil,
          "escaped duplicate keys rejected");

    for (NSData *bad in @[[NSData data], JSON(@[]),
                          (NSData *)[@"null" dataUsingEncoding:NSUTF8StringEncoding],
                          (NSData *)[@"{" dataUsingEncoding:NSUTF8StringEncoding],
                          (NSData *)[NSMutableData dataWithLength:16385]]) {
        Check(AQParseInstallationPolicy(bad, NULL) == nil,
              "nonobject, malformed, or oversized policy rejected");
    }
}

static void TestPeerCodeFacts(void) {
    NSError *error = nil;
    AQInstallationPolicy *policy = AQParseInstallationPolicy(JSON(PolicyFixture()), &error);
    Check(policy != nil, "peer policy fixture parses");
    if (!policy) return;
    Check(!AQSecurityTestEvaluatePeerCodeFacts(nil, policy, AQPeerBroker, NULL),
          "missing live-code facts rejected");
    Check(!AQSecurityTestEvaluatePeerCodeFacts(@{}, policy, AQPeerBroker, NULL),
          "incomplete live-code facts rejected");
    Check(!AQSecurityTestEvaluatePeerCodeFacts(@{}, nil, AQPeerBroker, NULL),
          "nil peer policy rejected");
    Check(!AQSecurityTestEvaluatePeerCodeFacts(@{}, policy, (AQPeerRole)99, NULL),
          "unknown pure-predicate peer role rejected");

    NSString *brokerRequirement = AQPeerSigningRequirement(policy, AQPeerBroker, &error);
    SecRequirementRef compiled = NULL;
    Check(brokerRequirement && SecRequirementCreateWithString(
        (__bridge CFStringRef)brokerRequirement, 0, &compiled) == errSecSuccess,
        "broker requirement is accepted by the OS compiler");
    if (compiled) CFRelease(compiled);
    Check([brokerRequirement containsString:@"ABCDE12345"] &&
          [brokerRequirement containsString:@"1111111111111111111111111111111111111111"],
          "broker requirement binds team and CodeDirectory revision");
    NSString *serviceRequirement = AQPeerSigningRequirement(policy, AQPeerService, NULL);
    Check([serviceRequirement containsString:@"com.argusromtoolkit.fixture-staging.service"] &&
          [serviceRequirement containsString:@"2222222222222222222222222222222222222222"],
          "service requirement binds service identity and revision");
    Check(AQPeerSigningRequirement(policy, (AQPeerRole)99, NULL) == nil,
          "unknown peer role rejected");
    Check(AQPeerSigningRequirement((AQInstallationPolicy *)NSNull.null,
                                   AQPeerBroker, NULL) == nil,
          "nil peer policy rejected");

    uint8_t brokerDigest[20];
    uint8_t serviceDigest[20];
    memset(brokerDigest, 0x11, sizeof(brokerDigest));
    memset(serviceDigest, 0x22, sizeof(serviceDigest));
    NSDictionary *brokerFacts = @{
        (__bridge id)kSecCodeInfoTeamIdentifier:@"ABCDE12345",
        (__bridge id)kSecCodeInfoIdentifier:@"com.argusromtoolkit.fixture-staging.broker",
        (__bridge id)kSecCodeInfoUnique:[NSData dataWithBytes:brokerDigest length:sizeof(brokerDigest)],
        (__bridge id)kSecCodeInfoMainExecutable:[NSURL fileURLWithPath:AQBrokerExecutablePath],
        (__bridge id)kSecCodeInfoFlags:@(kSecCodeSignatureRuntime),
        (__bridge id)kSecCodeInfoStatus:@(kSecCodeStatusValid),
        (__bridge id)kSecCodeInfoEntitlementsDict:@{
            @"keychain-access-groups": @[policy.keyAccessGroup]
        }
    };
    Check(AQSecurityTestEvaluatePeerCodeFacts(brokerFacts, policy, AQPeerBroker, &error),
          "approved broker facts satisfy the pure production predicate");
    NSMutableDictionary *directLaunchFacts = [brokerFacts mutableCopy];
    directLaunchFacts[(__bridge id)kSecCodeInfoMainExecutable] =
        [NSURL fileURLWithPath:@"/tmp/ArgusStagingBroker"];
    Check(!AQSecurityTestEvaluatePeerCodeFacts(directLaunchFacts, policy, AQPeerBroker, NULL),
          "direct launch from outside the approved protected ancestry is rejected");
    Check(!policy.isInstalledPolicy,
          "synthetic policy facts remain explicit non-production evidence");

    NSDictionary *serviceFacts = @{
        (__bridge id)kSecCodeInfoTeamIdentifier:@"ABCDE12345",
        (__bridge id)kSecCodeInfoIdentifier:@"com.argusromtoolkit.fixture-staging.service",
        (__bridge id)kSecCodeInfoUnique:[NSData dataWithBytes:serviceDigest length:sizeof(serviceDigest)],
        (__bridge id)kSecCodeInfoMainExecutable:[NSURL fileURLWithPath:AQServiceExecutablePath],
        (__bridge id)kSecCodeInfoFlags:@(kSecCodeSignatureRuntime),
        (__bridge id)kSecCodeInfoStatus:@(kSecCodeStatusValid),
        (__bridge id)kSecCodeInfoEntitlementsDict:@{}
    };
    Check(AQSecurityTestEvaluatePeerCodeFacts(serviceFacts, policy, AQPeerService, NULL),
          "approved non-login service facts satisfy the pure predicate");
    NSMutableDictionary *serviceWithGroup = [serviceFacts mutableCopy];
    serviceWithGroup[(__bridge id)kSecCodeInfoEntitlementsDict] =
        @{@"keychain-access-groups": @[policy.keyAccessGroup]};
    Check(!AQSecurityTestEvaluatePeerCodeFacts(serviceWithGroup, policy, AQPeerService, NULL),
          "service Keychain access-group entitlement rejected");

    NSArray *wrongFacts = @[
        @[(__bridge id)kSecCodeInfoTeamIdentifier, @"OTHER12345"],
        @[(__bridge id)kSecCodeInfoIdentifier, @"copied.broker"],
        @[(__bridge id)kSecCodeInfoUnique, (NSData *)[NSMutableData dataWithLength:19]],
        @[(__bridge id)kSecCodeInfoUnique, (NSData *)[NSMutableData dataWithLength:20]],
        @[(__bridge id)kSecCodeInfoMainExecutable, [NSURL fileURLWithPath:@"/tmp/ArgusStagingBroker"]],
        @[(__bridge id)kSecCodeInfoFlags, @0],
        @[(__bridge id)kSecCodeInfoFlags, @(kSecCodeSignatureRuntime | kSecCodeSignatureAdhoc)],
        @[(__bridge id)kSecCodeInfoStatus, @0],
        @[(__bridge id)kSecCodeInfoStatus, @(kSecCodeStatusValid | kSecCodeStatusDebugged)],
        @[(__bridge id)kSecCodeInfoEntitlementsDict, @"not-a-dictionary"],
        @[(__bridge id)kSecCodeInfoEntitlementsDict, @{@"keychain-access-groups": @[@"wrong.group"]}]
    ];
    for (NSArray *change in wrongFacts) {
        NSMutableDictionary *bad = [brokerFacts mutableCopy];
        bad[change[0]] = change[1];
        Check(!AQSecurityTestEvaluatePeerCodeFacts(bad, policy, AQPeerBroker, NULL),
              "wrong live-code fact rejected");
    }
    for (NSString *entitlement in @[@"com.apple.security.get-task-allow", @"get-task-allow",
        @"com.apple.security.cs.disable-library-validation",
        @"com.apple.security.cs.allow-dyld-environment-variables",
        @"com.apple.security.cs.allow-unsigned-executable-memory",
        @"com.apple.security.cs.allow-jit", @"com.apple.security.cs.debugger"]) {
        NSMutableDictionary *bad = [brokerFacts mutableCopy];
        bad[(__bridge id)kSecCodeInfoEntitlementsDict] = @{
            @"keychain-access-groups": @[policy.keyAccessGroup], entitlement: @YES
        };
        Check(!AQSecurityTestEvaluatePeerCodeFacts(bad, policy, AQPeerBroker, NULL),
              "debug or runtime-exception entitlement rejected");
    }
}

static void TestPeerExecutablePathExtraction(void) {
    CFURLRef validExecutable = CFURLCreateWithFileSystemPath(
        kCFAllocatorDefault, (__bridge CFStringRef)AQBrokerExecutablePath,
        kCFURLPOSIXPathStyle, false);
    Check(validExecutable != NULL, "construct bridgeable CFURL fixture");
    if (validExecutable) {
        NSDictionary *info = @{
            (__bridge id)kSecCodeInfoMainExecutable: (__bridge id)validExecutable
        };
        NSError *error = nil;
        NSString *path = nil;
        BOOL accepted = NO;
        BOOL threw = NO;
        @try {
            accepted = AQSecurityTestCopyPeerExecutablePath(info, &path, &error);
        } @catch (NSException *exception) {
            threw = YES;
        }
        Check(!threw, "CFURL executable metadata does not raise an exception");
        Check(accepted && [path isEqual:AQBrokerExecutablePath] && error == nil,
              "CFURL executable metadata yields its filesystem path");
        CFRelease(validExecutable);
    }

    NSArray<NSDictionary *> *malformed = @[
        @{},
        @{(__bridge id)kSecCodeInfoMainExecutable:
              @{@"path": AQBrokerExecutablePath}},
        @{(__bridge id)kSecCodeInfoMainExecutable: @42},
        @{(__bridge id)kSecCodeInfoMainExecutable: NSNull.null},
        @{(__bridge id)kSecCodeInfoMainExecutable: AQBrokerExecutablePath},
        @{(__bridge id)kSecCodeInfoMainExecutable:
              (NSURL * _Nonnull)[NSURL URLWithString:@"https://example.invalid/broker"]},
        @{(__bridge id)kSecCodeInfoMainExecutable:
              (NSURL * _Nonnull)[NSURL URLWithString:@"file://example.invalid/tmp/broker"]},
        @{(__bridge id)kSecCodeInfoMainExecutable:
              (NSURL * _Nonnull)[NSURL URLWithString:@"file:relative/broker"]},
        @{(__bridge id)kSecCodeInfoMainExecutable:
              (NSURL * _Nonnull)[NSURL URLWithString:@"file://localhost"]}
    ];
    for (NSDictionary *info in malformed) {
        NSError *error = nil;
        NSString *path = @"sentinel";
        BOOL accepted = NO;
        BOOL threw = NO;
        @try {
            accepted = AQSecurityTestCopyPeerExecutablePath(info, &path, &error);
        } @catch (NSException *exception) {
            threw = YES;
        }
        Check(!threw, "malformed executable metadata does not raise an exception");
        Check(!accepted && path == nil &&
              [error.domain isEqual:AQSecurityErrorDomain] &&
              error.code == AQSecurityUntrustedPeer,
              "malformed executable metadata fails closed");
    }

    NSURL *localhostExecutable = [NSURL URLWithString:@"file://localhost/tmp/broker"];
    NSDictionary *localhostInfo = @{
        (__bridge id)kSecCodeInfoMainExecutable: localhostExecutable
    };
    NSError *localhostError = nil;
    NSString *localhostPath = nil;
    Check(AQSecurityTestCopyPeerExecutablePath(localhostInfo, &localhostPath, &localhostError) &&
          [localhostPath isEqual:@"/tmp/broker"] && localhostError == nil,
          "localhost file URL executable metadata yields an absolute path");

    NSError *nilInfoError = nil;
    NSString *nilInfoPath = @"sentinel";
    Check(!AQSecurityTestCopyPeerExecutablePath(nil, &nilInfoPath, &nilInfoError) &&
          nilInfoPath == nil && [nilInfoError.domain isEqual:AQSecurityErrorDomain] &&
          nilInfoError.code == AQSecurityUntrustedPeer,
          "nil executable metadata fails closed");

    NSError *nonDictionaryError = nil;
    NSString *nonDictionaryPath = @"sentinel";
    Check(!AQSecurityTestCopyPeerExecutablePath((NSDictionary *)NSNull.null,
                                                &nonDictionaryPath, &nonDictionaryError) &&
          nonDictionaryPath == nil &&
          [nonDictionaryError.domain isEqual:AQSecurityErrorDomain] &&
          nonDictionaryError.code == AQSecurityUntrustedPeer,
          "non-dictionary executable metadata fails closed");

    NSError *nullPathError = nil;
    Check(!AQSecurityTestCopyPeerExecutablePath(localhostInfo, NULL, &nullPathError) &&
          [nullPathError.domain isEqual:AQSecurityErrorDomain] &&
          nullPathError.code == AQSecurityUntrustedPeer,
          "missing executable path output fails closed");
}

static void TestProtectedPathsAndIdentity(void) {
    NSError *error = nil;
    Check(AQValidateProtectedPath(@"/private", YES, 0755, &error) && error == nil,
          "real root-owned directory admits descriptor validation");
    Check(AQValidateProtectedPath(@"/usr/bin/true", NO, 0755, NULL),
          "real root-owned executable admits descriptor validation");
    Check(!AQValidateProtectedPath(@"/var/db", YES, 0755, NULL),
          "symlinked ancestry rejected");
    Check(!AQValidateProtectedPath(NSHomeDirectory(), YES, 0755, NULL),
          "user-owned ancestry rejected");
    Check(!AQValidateProtectedPath(@"/private", YES, 0700, NULL),
          "caller cannot weaken the exact installed-directory mode");
    for (NSString *bad in @[@"relative", @"/private/../private", @"/private//var",
                            @"/private/./var", @"/private/var/"]) {
        Check(!AQValidateProtectedPath(bad, YES, 0755, NULL),
              "ambiguous lexical path rejected");
    }
    Check(!AQValidateProtectedPath((NSString *)@[], YES, 0755, NULL),
          "non-string protected path rejected");
    Check(!AQValidateProtectedPath([NSString stringWithFormat:@"/private%cvar", 0],
                                   YES, 0755, NULL),
          "NUL-containing protected path rejected");
    NSString *overlongPath = [@"/" stringByPaddingToLength:PATH_MAX withString:@"a"
                                            startingAtIndex:0];
    Check(!AQValidateProtectedPath(overlongPath, YES, 0755, NULL),
          "overlong protected path rejected");

    char directoryTemplate[] = "/tmp/aq-security-XXXXXX";
    char *directory = mkdtemp(directoryTemplate);
    Check(directory != NULL, "private test directory created");
    if (directory) {
        int fd = open(directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
        Check(fd >= 0, "private test directory opened");
        if (fd >= 0) {
            Check(chmod(directory, 0700) == 0, "test directory mode set");
            Check(AQSecurityTestValidateDirectoryFD(fd, geteuid(), 0700, NULL),
                  "owned 0700 directory satisfies protected-fd predicate");
            Check(!AQSecurityTestValidateDirectoryFD(fd, geteuid() + 1, 0700, NULL),
                  "wrong directory owner rejected");
            Check(chmod(directory, 0755) == 0, "test directory mode changed");
            Check(!AQSecurityTestValidateDirectoryFD(fd, geteuid(), 0700, NULL),
                  "non-0700 protected directory rejected");
            Check(chmod(directory, 0700) == 0, "test directory mode restored");

            uuid_t qualifier;
            acl_t acl = acl_init(1);
            acl_entry_t entry = NULL;
            acl_permset_t perms = NULL;
            BOOL prepared = acl && mbr_uid_to_uuid(geteuid(), qualifier) == 0 &&
                acl_create_entry(&acl, &entry) == 0 &&
                acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0 &&
                acl_set_qualifier(entry, qualifier) == 0 &&
                acl_get_permset(entry, &perms) == 0 &&
                acl_add_perm(perms, ACL_READ_DATA) == 0 &&
                acl_set_permset(entry, perms) == 0 && acl_valid(acl) == 0;
            BOOL installed = prepared && acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED) == 0;
            if (acl) acl_free(acl);
            Check(installed, "test ACL applied to directory");
            Check(!AQSecurityTestValidateDirectoryFD(fd, geteuid(), 0700, NULL),
                  "directory with an extended ACL rejected");
            acl_t empty = acl_init(0);
            if (empty) {
                acl_set_fd_np(fd, empty, ACL_TYPE_EXTENDED);
                acl_free(empty);
            }
            close(fd);
        }
        rmdir(directory);
    }

    char fileDirectoryTemplate[] = "/tmp/aq-security-files-XXXXXX";
    char *fileDirectory = mkdtemp(fileDirectoryTemplate);
    Check(fileDirectory != NULL, "private file test directory created");
    if (fileDirectory) {
        char filePath[PATH_MAX];
        char hardLinkPath[PATH_MAX];
        char fifoPath[PATH_MAX];
        snprintf(filePath, sizeof(filePath), "%s/file", fileDirectory);
        snprintf(hardLinkPath, sizeof(hardLinkPath), "%s/hard-link", fileDirectory);
        snprintf(fifoPath, sizeof(fifoPath), "%s/fifo", fileDirectory);

        int fileFD = open(filePath, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0600);
        Check(fileFD >= 0, "private regular file created");
        if (fileFD >= 0) {
            Check(fchmod(fileFD, 0644) == 0, "test file mode set");
            Check(AQSecurityTestValidateFileFD(fileFD, geteuid(), 0644, NULL),
                  "owned 0644 single-link file satisfies protected-fd predicate");
            Check(!AQSecurityTestValidateFileFD(fileFD, geteuid() + 1, 0644, NULL),
                  "wrong file owner rejected");
            Check(fchmod(fileFD, 0664) == 0, "test file group-write mode set");
            Check(!AQSecurityTestValidateFileFD(fileFD, geteuid(), 0644, NULL),
                  "writable protected file mode rejected");
            Check(fchmod(fileFD, 0755) == 0, "test executable mode set");
            Check(AQSecurityTestValidateFileFD(fileFD, geteuid(), 0755, NULL),
                  "owned 0755 executable file satisfies protected-fd predicate");
            Check(link(filePath, hardLinkPath) == 0, "second file hard link created");
            Check(!AQSecurityTestValidateFileFD(fileFD, geteuid(), 0755, NULL),
                  "multiply linked protected file rejected");
            unlink(hardLinkPath);
            close(fileFD);
        }
        unlink(filePath);

        Check(mkfifo(fifoPath, 0644) == 0, "test FIFO created");
        int fifoFD = open(fifoPath, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        Check(fifoFD >= 0, "test FIFO opened without blocking");
        if (fifoFD >= 0) {
            Check(!AQSecurityTestValidateFileFD(fifoFD, geteuid(), 0644, NULL),
                  "special file rejected by protected-file predicate");
            close(fifoFD);
        }
        unlink(fifoPath);
        rmdir(fileDirectory);
    }

    Check(AQSecurityTestEvaluateNonLoginAccountFacts(@"*", @"/usr/bin/false"),
          "false-shell service marker accepted");
    Check(AQSecurityTestEvaluateNonLoginAccountFacts(@"*", @"/sbin/nologin"),
          "nologin service marker accepted");
    Check(!AQSecurityTestEvaluateNonLoginAccountFacts(nil, @"/usr/bin/false"),
          "missing password marker rejected");
    Check(!AQSecurityTestEvaluateNonLoginAccountFacts(@"********", @"/usr/bin/false"),
          "reusable or unknown password marker rejected");
    Check(!AQSecurityTestEvaluateNonLoginAccountFacts(@"*", @"/bin/zsh"),
          "interactive login shell rejected");
    Check(!AQSecurityTestEvaluateNonLoginAccountFacts(@"*", nil),
          "missing shell record rejected");

    NSMutableDictionary *loginFixture = [PolicyFixture() mutableCopy];
    loginFixture[@"service_uid"] = @(geteuid());
    loginFixture[@"owner_uid"] = @(geteuid() == 1 ? 2 : 1);
    AQInstallationPolicy *loginPolicy = TrustedTestPolicy(loginFixture, NULL);
    Check(loginPolicy && !AQValidateNonLoginServiceIdentity(loginPolicy, NULL),
          "ordinary login account cannot become the service identity");
    NSMutableDictionary *missingFixture = [PolicyFixture() mutableCopy];
    missingFixture[@"service_uid"] = @4294967294ULL;
    missingFixture[@"owner_uid"] = @1;
    AQInstallationPolicy *missingPolicy = TrustedTestPolicy(missingFixture, NULL);
    Check(missingPolicy && !AQValidateNonLoginServiceIdentity(missingPolicy, NULL),
          "missing pinned service account fails closed");
    AQInstallationPolicy *untrusted = AQParseInstallationPolicy(JSON(PolicyFixture()), NULL);
    Check(untrusted && AQOpenProductionStagingRoot(untrusted, NULL) < 0,
          "caller-supplied policy cannot open production staging root");
    Check(missingPolicy && AQOpenProductionStagingRoot(missingPolicy, NULL) < 0,
          "fixed staging root fails closed without its installed service identity");
}

static void TestOwnerKeyPredicate(void) {
    NSError *error = nil;
    AQInstallationPolicy *policy = AQParseInstallationPolicy(JSON(PolicyFixture()), NULL);
    SecAccessControlRef access = SecAccessControlCreateWithFlags(NULL,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlUserPresence | kSecAccessControlPrivateKeyUsage, NULL);
    Check(access != NULL, "production owner-key access control can be constructed");
    if (!policy || !access) {
        if (access) CFRelease(access);
        return;
    }
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecAttrAccessGroup: policy.keyAccessGroup,
        (__bridge id)kSecAttrApplicationTag:
            (NSData *)[policy.keyTag dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessControl: (__bridge id)access
    };
    Check(AQSecurityTestEvaluateOwnerKeyAttributes(attributes, policy, &error),
          "strict owner-key predicate accepts expected Secure Enclave constraints");
    for (id field in attributes) {
        NSMutableDictionary *missing = [attributes mutableCopy];
        [missing removeObjectForKey:field];
        Check(!AQSecurityTestEvaluateOwnerKeyAttributes(missing, policy, NULL),
              "missing actual owner-key attribute rejected");
    }
    SecAccessControlRef weak = SecAccessControlCreateWithFlags(NULL,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlPrivateKeyUsage, NULL);
    NSMutableDictionary *bad = [attributes mutableCopy];
    bad[(__bridge id)kSecAttrAccessControl] = (__bridge id)weak;
    Check(!AQSecurityTestEvaluateOwnerKeyAttributes(bad, policy, NULL),
          "owner key lacking user presence rejected");
    NSArray *wrongOwnerAttributes = @[
        @[(__bridge id)kSecAttrKeyType, @"not-ec"],
        @[(__bridge id)kSecAttrKeyClass, (__bridge id)kSecAttrKeyClassPublic],
        @[(__bridge id)kSecAttrAccessGroup, @"wrong.team.shared"],
        @[(__bridge id)kSecAttrApplicationTag,
          (NSData *)[@"wrong-tag" dataUsingEncoding:NSUTF8StringEncoding]],
    ];
    for (NSArray *change in wrongOwnerAttributes) {
        NSMutableDictionary *wrong = [attributes mutableCopy];
        wrong[change[0]] = change[1];
        Check(!AQSecurityTestEvaluateOwnerKeyAttributes(wrong, policy, NULL),
              "wrong owner-key type, class, access group or tag rejected");
    }
    bad[(__bridge id)kSecAttrAccessControl] = (__bridge id)access;
    bad[(__bridge id)kSecAttrKeySizeInBits] = @384;
    Check(!AQSecurityTestEvaluateOwnerKeyAttributes(bad, policy, NULL),
          "non-P-256 owner key rejected");
    bad[(__bridge id)kSecAttrKeySizeInBits] = @256;
    bad[(__bridge id)kSecAttrTokenID] = @"not-secure-enclave";
    Check(!AQSecurityTestEvaluateOwnerKeyAttributes(bad, policy, NULL),
          "non-Secure-Enclave owner key rejected");
    bad[(__bridge id)kSecAttrTokenID] = (__bridge id)kSecAttrTokenIDSecureEnclave;
    bad[(__bridge id)kSecAttrSynchronizable] = @YES;
    Check(!AQSecurityTestEvaluateOwnerKeyAttributes(bad, policy, NULL),
          "synchronizable owner key rejected");
    bad[(__bridge id)kSecAttrSynchronizable] = @"not-a-boolean";
    Check(!AQSecurityTestEvaluateOwnerKeyAttributes(bad, policy, NULL),
          "non-boolean synchronizable marker rejected");
    bad[(__bridge id)kSecAttrSynchronizable] = @NO;
    Check(AQSecurityTestEvaluateOwnerKeyAttributes(bad, policy, NULL),
          "explicitly non-synchronizable owner key accepted");
    Check(!AQSecurityTestEvaluateOwnerKeyAttributes(nil, policy, NULL),
          "nil owner-key attributes rejected");
    Check(!AQSecurityTestEvaluateOwnerKeyAttributes(attributes, nil, NULL),
          "nil policy owner-key attributes rejected");
    if (weak) CFRelease(weak);
    if (access) CFRelease(access);
}

static void TestOwnerSignatureAndConsent(void) {
    NSData *envelope = [@"{\"operation\":\"stage\",\"sequence\":1}" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *keyAttributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)keyAttributes, NULL);
    SecKeyRef publicKey = privateKey ? SecKeyCopyPublicKey(privateKey) : NULL;
    NSData *publicBytes = publicKey
        ? CFBridgingRelease(SecKeyCopyExternalRepresentation(publicKey, NULL)) : nil;
    if (publicKey) CFRelease(publicKey);
    Check(privateKey != NULL && publicBytes.length == 65,
          "software P-256 fixture generated for non-production verification only");

    AQInstallationPolicy *untrusted = AQParseInstallationPolicy(JSON(PolicyFixture()), NULL);
    Check(!AQVerifyOwnerSignature(untrusted, envelope,
                                  (NSData *)[NSMutableData dataWithLength:8], NULL),
          "caller-supplied policy cannot verify an owner signature");
    Check(!AQVerifyOwnerSignature(untrusted, [NSData data],
                                  (NSData *)[NSMutableData dataWithLength:72], NULL),
          "empty envelope rejected before policy trust");
    Check(!AQVerifyOwnerSignature(untrusted, envelope,
                                  (NSData *)[NSMutableData dataWithLength:7], NULL),
          "undersized signature rejected");
    Check(!AQVerifyOwnerSignature(untrusted, envelope,
                                  (NSData *)[NSMutableData dataWithLength:73], NULL),
          "oversized signature rejected");

    AQInstallationPolicy *trusted = publicBytes
        ? TrustedTestPolicy(PolicyFixtureWithPublicKey(publicBytes), NULL) : nil;
    NSData *signature = privateKey ? CFBridgingRelease(SecKeyCreateSignature(privateKey,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)envelope, NULL)) : nil;
    Check(trusted && signature && AQVerifyOwnerSignature(trusted, envelope, signature, NULL),
          "pinned P-256 key verifies exact canonical envelope bytes");
    Check(trusted && signature && !AQVerifyOwnerSignature(trusted,
        (NSData *)[@"tampered" dataUsingEncoding:NSUTF8StringEncoding], signature, NULL),
          "tampered envelope invalidates signature");
    if (privateKey) CFRelease(privateKey);

    __block NSUInteger completions = 0;
    __block BOOL allMain = YES;
    AQRequestOwnerSignature(untrusted, envelope, ^(NSData *result, NSError *failure) {
        Check(!result && failure.code == AQSecurityUntrustedInstallation,
              "untrusted consent policy rejected before UI or Keychain");
        allMain = allMain && NSThread.isMainThread;
        completions++;
    });
    AQRequestOwnerSignature(untrusted, [NSData data], ^(NSData *result, NSError *failure) {
        Check(!result && failure.code == AQSecurityInvalidInput,
              "empty consent envelope rejected without an owner prompt");
        allMain = allMain && NSThread.isMainThread;
        completions++;
    });
    if (trusted) {
        AQRequestOwnerSignature(trusted, envelope, ^(NSData *result, NSError *failure) {
            Check(!result && failure.code == AQSecurityUntrustedPeer,
                  "test-trusted policy with copied broker code cannot reach consent UI");
            allMain = allMain && NSThread.isMainThread;
            completions++;
        });
    } else {
        allMain = NO;
        completions++;
    }
    AQEnrollOwnerKey(untrusted, ^(NSData *result, NSError *failure) {
        Check(!result && failure.code == AQSecurityUntrustedInstallation,
              "unenrolled untrusted policy cannot reach enrollment prompt");
        allMain = allMain && NSThread.isMainThread;
        completions++;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (completions != 4 && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(completions == 4, "all consent precondition failures complete");
    Check(allMain, "consent completions run on the main queue");
}

static void TestXPCBoundary(void) {
    NSError *error = nil;
    Check(AQAuthenticatedPeerAPIsAvailable(&error) && error == nil,
          "host runtime provides macOS 12 authenticated XPC primitives");
    AQInstallationPolicy *untrusted = AQParseInstallationPolicy(JSON(PolicyFixture()), NULL);
    AQInstallationPolicy *trusted = TrustedTestPolicy(PolicyFixture(), NULL);
    Check(untrusted != nil && trusted != nil, "XPC policy fixtures parse");
    if (!untrusted || !trusted) return;

    AQSecurityTestSetAuthenticatedPeerAPIsUnavailable(YES);
    Check(!AQAuthenticatedPeerAPIsAvailable(&error) &&
          error.code == AQSecurityUnsupportedPlatform,
          "missing per-message peer API fails closed");
    xpc_object_t unavailableProbe = xpc_dictionary_create(NULL, NULL, 0);
    Check(!AQConfigurePeerRequirement((xpc_connection_t)unavailableProbe, trusted,
          AQPeerBroker, &error) && error.code == AQSecurityUnsupportedPlatform,
          "connection requirement refuses unavailable peer APIs");
    Check(!AQValidatePeerMessage(unavailableProbe, trusted, AQPeerBroker, &error) &&
          error.code == AQSecurityUnsupportedPlatform,
          "message validation refuses unavailable peer APIs");
    AQSecurityTestSetAuthenticatedPeerAPIsUnavailable(NO);
    Check(AQAuthenticatedPeerAPIsAvailable(&error) && error == nil,
          "real host APIs resume after explicit test-only unavailability");

    xpc_object_t notConnection = xpc_dictionary_create(NULL, NULL, 0);
    Check(!AQConfigurePeerRequirement(notConnection, untrusted, AQPeerBroker, &error) &&
          error.code == AQSecurityUntrustedInstallation,
          "caller-supplied policy cannot configure a peer requirement");
    Check(!AQConfigurePeerRequirement(notConnection, trusted, AQPeerBroker, &error) &&
          error.code == AQSecurityInvalidInput,
          "non-connection XPC object rejected");
    xpc_object_t local = xpc_dictionary_create(NULL, NULL, 0);
    Check(!AQValidatePeerMessage(local, trusted, AQPeerBroker, &error) &&
          error.code == AQSecurityUntrustedPeer,
          "locally constructed dictionary has no per-message peer authority");
    xpc_object_t spoofedMetadata = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(spoofedMetadata, "pid", getpid());
    uint8_t syntheticAuditToken[32] = {0};
    xpc_dictionary_set_data(spoofedMetadata, "audit_token", syntheticAuditToken,
                            sizeof(syntheticAuditToken));
    Check(!AQValidatePeerMessage(spoofedMetadata, trusted, AQPeerBroker, &error) &&
          error.code == AQSecurityUntrustedPeer,
          "caller-supplied PID and audit-token fields never grant authority");

    xpc_connection_t listener = xpc_connection_create(NULL, NULL);
    Check(listener != NULL, "anonymous XPC listener created");
    if (listener)
        xpc_connection_set_event_handler(listener, ^(__unused xpc_object_t event) {});
    Check(listener && AQConfigurePeerRequirement(listener, trusted, AQPeerBroker, &error),
          "macOS accepts the generated peer requirement on a new inactive connection");
    if (listener) {
        xpc_connection_activate(listener);
        xpc_connection_cancel(listener);
    }

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL livePeer = NO;
    __block BOOL validationFailedClosed = NO;
    xpc_connection_t peerListener = xpc_connection_create(NULL, NULL);
    xpc_connection_set_event_handler(peerListener, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_CONNECTION) {
            xpc_connection_t peer = event;
            xpc_connection_set_event_handler(peer, ^(xpc_object_t message) {
                if (xpc_get_type(message) == XPC_TYPE_DICTIONARY) {
                    xpc_connection_t remote = xpc_dictionary_get_remote_connection(message);
                    BOOL uidMatches = remote && xpc_connection_get_euid(remote) == geteuid();
                    livePeer = uidMatches && AQSecurityTestMessageHasLivePeer(message, NULL);
                    validationFailedClosed = !AQValidatePeerMessage(message, trusted,
                        AQPeerBroker, NULL);
                    dispatch_semaphore_signal(done);
                }
            });
            xpc_connection_activate(peer);
        }
    });
    xpc_endpoint_t endpoint = xpc_endpoint_create(peerListener);
    xpc_connection_activate(peerListener);
    xpc_connection_t client = xpc_connection_create_from_endpoint(endpoint);
    xpc_connection_set_event_handler(client, ^(__unused xpc_object_t event) {});
    xpc_connection_activate(client);
    xpc_object_t probe = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(probe, "probe", "live-peer-identity");
    xpc_connection_send_message(client, probe);
    long waitResult = dispatch_semaphore_wait(done,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    xpc_connection_cancel(client);
    xpc_connection_cancel(peerListener);
    Check(waitResult == 0 && livePeer,
          "received message resolves to its live peer SecCode and UID");
    Check(validationFailedClosed,
          "unapproved process identity still fails production validation");
}

int AQRunSecurityTests(void) {
    failures = 0;
    checks = 0;
    @autoreleasepool {
        TestPolicyParsing();
        TestPeerCodeFacts();
    TestPeerExecutablePathExtraction();
        TestProtectedPathsAndIdentity();
        TestOwnerKeyPredicate();
        TestOwnerSignatureAndConsent();
        TestXPCBoundary();
    }
    fprintf(stdout, "security tests: %d checks, %d failures\n", checks, failures);
    return failures;
}

#ifdef AQ_SECURITY_TEST_MAIN
int main(void) {
    return AQRunSecurityTests() == 0 ? 0 : 1;
}
#endif
