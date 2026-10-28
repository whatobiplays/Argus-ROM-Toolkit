#import "AQSecurity.h"
#import "AQJSON.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#include <sys/acl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <pwd.h>
#include <grp.h>
#include <unistd.h>
#include <limits.h>
#include <dlfcn.h>

#if !defined(__APPLE__) || !TARGET_OS_OSX
#error "AQSecurity is a macOS-only production security boundary."
#endif

#if __MAC_OS_X_VERSION_MIN_REQUIRED < 120000
#error "AQSecurity requires the macOS 12.0 deployment target or later."
#endif

NSString *const AQSecurityErrorDomain = @"com.argusromtoolkit.fixture-staging.security";
NSString *const AQInstallationPath = @"/Library/PrivilegedHelperTools/ArgusFixtureStaging/installation.json";
NSString *const AQProductionStagingRoot = @"/private/var/db/argus-qualification/staging";
NSString *const AQBrokerExecutablePath = @"/Library/PrivilegedHelperTools/ArgusFixtureStaging/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker";
NSString *const AQServiceExecutablePath = @"/Library/PrivilegedHelperTools/ArgusFixtureStaging/argus-staging-service";
NSString *const AQMachServiceName = @"com.argusromtoolkit.fixture-staging";
static NSString *const AQBrokerID = @"com.argusromtoolkit.fixture-staging.broker";
static NSString *const AQServiceID = @"com.argusromtoolkit.fixture-staging.service";
static NSString *const AQOwnerKeyTag = @"com.argusromtoolkit.fixture-staging.owner-consent.v1";
static const NSUInteger AQMaxPolicyBytes = 16384;
static const NSUInteger AQMaxEnvelopeBytes = 65536;

/* Resolve both public entry points explicitly. The SDK assigns macOS 12.0 to
 * the XPC setter but no later availability version to SecCodeCreateWithXPCMessage;
 * production requires both to exist in the running Security and XPC frameworks. */
typedef int (*AQSetPeerCodeSigningRequirementFunction)(xpc_connection_t, const char *);
typedef OSStatus (*AQCreateSecCodeWithXPCMessageFunction)(xpc_object_t, SecCSFlags, SecCodeRef *);
static AQSetPeerCodeSigningRequirementFunction AQSetPeerCodeSigningRequirement;
static AQCreateSecCodeWithXPCMessageFunction AQCreateSecCodeWithXPCMessage;
#if defined(AQ_SECURITY_TESTING)
static BOOL AQTestPeerAPIsForcedUnavailable;
#endif

static void AQResolveAuthenticatedPeerAPIs(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        AQSetPeerCodeSigningRequirement = (AQSetPeerCodeSigningRequirementFunction)dlsym(
            RTLD_DEFAULT, "xpc_connection_set_peer_code_signing_requirement");
        AQCreateSecCodeWithXPCMessage = (AQCreateSecCodeWithXPCMessageFunction)dlsym(
            RTLD_DEFAULT, "SecCodeCreateWithXPCMessage");
    });
}

@interface AQInstallationPolicy ()
@property(nonatomic, readwrite, copy) NSString *teamIdentifier;
@property(nonatomic, readwrite, copy) NSString *brokerCDHash;
@property(nonatomic, readwrite, copy) NSString *serviceCDHash;
@property(nonatomic, readwrite) uid_t ownerUID;
@property(nonatomic, readwrite) uid_t serviceUID;
@property(nonatomic, readwrite, copy) NSString *keyAccessGroup;
@property(nonatomic, readwrite, copy) NSString *keyTag;
@property(nonatomic, readwrite, copy) NSData *ownerPublicKey;
@property(nonatomic, readwrite, getter=isInstalledPolicy) BOOL installedPolicy;
@property(nonatomic, copy) NSDictionary *fields;
/* Set only by the test-only trust helper in an AQ_SECURITY_TESTING build. */
@property(nonatomic, readwrite) BOOL testingAuthority;
- (instancetype)initWithFields:(NSDictionary *)fields publicKey:(NSData *)publicKey;
@end

@implementation AQInstallationPolicy
- (instancetype)initWithFields:(NSDictionary *)fields publicKey:(NSData *)publicKey {
    if ((self = [super init])) {
        _fields = [fields copy];
        _teamIdentifier = fields[@"team_id"];
        _brokerCDHash = fields[@"broker_cdhash"];
        _serviceCDHash = fields[@"service_cdhash"];
        _ownerUID = [fields[@"owner_uid"] unsignedIntValue];
        _serviceUID = [fields[@"service_uid"] unsignedIntValue];
        _keyAccessGroup = fields[@"key_access_group"];
        _keyTag = fields[@"key_tag"];
        _ownerPublicKey = [publicKey copy];
        _testingAuthority = NO;
    }
    return self;
}
@end

static BOOL AQFail(NSError **error, AQSecurityError code, NSString *description) {
    if (error) *error = [NSError errorWithDomain:AQSecurityErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey:description}];
    return NO;
}

static BOOL AQASCIIString(id value, NSUInteger length, NSString *alphabet) {
    if (![value isKindOfClass:NSString.class] || [value length] != length) return NO;
    return [value rangeOfCharacterFromSet:
        [[NSCharacterSet characterSetWithCharactersInString:alphabet] invertedSet]].location == NSNotFound;
}

static BOOL AQUnsignedInteger(id value, uint64_t minimum, uint64_t maximum) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()
        || CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    long long integer = [value longLongValue];
    return integer >= 0 && (uint64_t)integer >= minimum && (uint64_t)integer <= maximum;
}

static SecKeyRef AQCreatePublicKey(NSData *data) CF_RETURNS_RETAINED {
    if (data.length != 65 || ((const uint8_t *)data.bytes)[0] != 4) return NULL;
    return SecKeyCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)@{
        (__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits:@256}, NULL);
}

AQInstallationPolicy *AQParseInstallationPolicy(NSData *data, NSError **error) {
    if (error) *error = nil;
    if (![data isKindOfClass:NSData.class] || data.length == 0 || data.length > AQMaxPolicyBytes) {
        AQFail(error, AQSecurityInvalidPolicy, @"Installation policy must contain 1..16384 bytes."); return nil;
    }
    NSData *snapshot = [data copy];
    id fields = AQParseJSON(snapshot, NULL);
    NSSet *expected = [NSSet setWithArray:@[@"schema", @"team_id", @"broker_cdhash", @"service_cdhash",
        @"owner_uid", @"service_uid", @"key_access_group", @"key_tag", @"owner_public_key"]];
    if (![fields isKindOfClass:NSDictionary.class] ||
        ![[NSSet setWithArray:[fields allKeys]] isEqualToSet:expected]) {
        AQFail(error, AQSecurityInvalidPolicy, @"Installation policy must have exactly nine unique supported fields."); return nil;
    }
    if (!AQUnsignedInteger(fields[@"schema"], 1, 1) ||
        !AQASCIIString(fields[@"team_id"], 10, @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") ||
        !AQASCIIString(fields[@"broker_cdhash"], 40, @"0123456789abcdef") ||
        !AQASCIIString(fields[@"service_cdhash"], 40, @"0123456789abcdef") ||
        !AQUnsignedInteger(fields[@"owner_uid"], 1, UINT32_MAX - 1) ||
        !AQUnsignedInteger(fields[@"service_uid"], 1, UINT32_MAX - 1) ||
        [fields[@"owner_uid"] isEqual:fields[@"service_uid"]] ||
        ![fields[@"key_access_group"] isEqual:[NSString stringWithFormat:@"%@.%@", fields[@"team_id"], AQBrokerID]] ||
        ![fields[@"key_tag"] isEqual:AQOwnerKeyTag]) {
        AQFail(error, AQSecurityInvalidPolicy, @"Installation policy fields violate the production identity schema."); return nil;
    }
    NSData *publicKey = nil;
    if (fields[@"owner_public_key"] != NSNull.null) {
        id base64 = fields[@"owner_public_key"];
        if ([base64 isKindOfClass:NSString.class]) publicKey = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
        SecKeyRef key = AQCreatePublicKey(publicKey);
        BOOL valid = key && [[publicKey base64EncodedStringWithOptions:0] isEqual:base64];
        if (key) CFRelease(key);
        if (!valid) { AQFail(error, AQSecurityInvalidPolicy, @"Owner public key must be canonical base64 of a P-256 public point."); return nil; }
    }
    return [[AQInstallationPolicy alloc] initWithFields:fields publicKey:publicKey];
}

static BOOL AQEvaluatePeerCodeFacts(NSDictionary *info, AQInstallationPolicy *policy, AQPeerRole role, NSError **error) {
    if (error) *error = nil;
    if (![info isKindOfClass:NSDictionary.class] || !policy || (role != AQPeerBroker && role != AQPeerService))
        return AQFail(error, AQSecurityUntrustedPeer, @"Unsupported peer identity facts.");
    NSString *identifier = role == AQPeerBroker ? AQBrokerID : AQServiceID;
    NSString *path = role == AQPeerBroker ? AQBrokerExecutablePath : AQServiceExecutablePath;
    NSString *hash = role == AQPeerBroker ? policy.brokerCDHash : policy.serviceCDHash;
    NSData *digest = info[(__bridge id)kSecCodeInfoUnique];
    NSURL *executable = info[(__bridge id)kSecCodeInfoMainExecutable];
    NSNumber *flags = info[(__bridge id)kSecCodeInfoFlags];
    NSNumber *status = info[(__bridge id)kSecCodeInfoStatus];
    NSMutableString *hex = [NSMutableString string];
    if ([digest isKindOfClass:NSData.class] && digest.length == 20) {
        const uint8_t *bytes = digest.bytes;
        for (NSUInteger i = 0; i < digest.length; i++) [hex appendFormat:@"%02x", bytes[i]];
    }
    if (![info[(__bridge id)kSecCodeInfoTeamIdentifier] isEqual:policy.teamIdentifier] ||
        ![info[(__bridge id)kSecCodeInfoIdentifier] isEqual:identifier] || ![hex isEqual:hash] ||
        ![executable isKindOfClass:NSURL.class] || !executable.isFileURL || ![executable.path isEqual:path] ||
        !AQUnsignedInteger(flags, 0, UINT32_MAX) || !AQUnsignedInteger(status, 0, UINT32_MAX) ||
        !(flags.unsignedIntValue & kSecCodeSignatureRuntime) || (flags.unsignedIntValue & kSecCodeSignatureAdhoc) ||
        !(status.unsignedIntValue & kSecCodeStatusValid) || (status.unsignedIntValue & kSecCodeStatusDebugged))
        return AQFail(error, AQSecurityUntrustedPeer, @"Peer identity, installed revision, path or runtime status is not approved.");
    id entitlements = info[(__bridge id)kSecCodeInfoEntitlementsDict] ?: @{};
    if (![entitlements isKindOfClass:NSDictionary.class])
        return AQFail(error, AQSecurityUntrustedPeer, @"Peer entitlements are not a dictionary.");
    for (NSString *name in @[@"get-task-allow", @"com.apple.security.get-task-allow",
        @"com.apple.security.cs.disable-library-validation", @"com.apple.security.cs.allow-dyld-environment-variables",
        @"com.apple.security.cs.allow-unsigned-executable-memory", @"com.apple.security.cs.allow-jit",
        @"com.apple.security.cs.debugger"]) {
        id value = entitlements[name];
        if (value && (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() || [value boolValue]))
            return AQFail(error, AQSecurityUntrustedPeer, @"Peer contains a forbidden runtime exception entitlement.");
    }
    id groups = entitlements[@"keychain-access-groups"];
    if ((role == AQPeerBroker && ![groups isEqual:@[policy.keyAccessGroup]]) ||
        (role == AQPeerService && groups && ![groups isEqual:@[]]))
        return AQFail(error, AQSecurityUntrustedPeer, @"Peer Keychain access-group entitlement is not approved.");
    return YES;
}

/* Extracts the executable path from the CFURL supplied by the code-signing
 * API. The value is intentionally checked before browsing it; a hostile or
 * malformed metadata dictionary must fail closed rather than reach a
 * dictionary-only method on another object type. The host is validated before
 * asking for the path because NSURL path values omit any file URL authority. */
static BOOL AQCopyPeerExecutablePath(NSDictionary *info, NSString **path, NSError **error) {
    if (error) *error = nil;
    if (path) *path = nil;
    if (![info isKindOfClass:NSDictionary.class] || path == NULL)
        return AQFail(error, AQSecurityUntrustedPeer, @"Peer executable metadata is unavailable.");
    id value = info[(__bridge id)kSecCodeInfoMainExecutable];
    if (![value isKindOfClass:NSURL.class])
        return AQFail(error, AQSecurityUntrustedPeer, @"Peer executable metadata is not a URL.");
    NSURL *executable = (NSURL *)value;
    NSString *host = executable.isFileURL ? executable.host : nil;
    BOOL localHost = executable.isFileURL &&
        (host == nil || host.length == 0 || [host caseInsensitiveCompare:@"localhost"] == NSOrderedSame);
    NSString *candidate = localHost ? executable.path : nil;
    if (![candidate isKindOfClass:NSString.class] || candidate.length == 0 || !candidate.isAbsolutePath)
        return AQFail(error, AQSecurityUntrustedPeer,
                      @"Peer executable URL is not local or has no absolute filesystem path.");
    *path = [candidate copy];
    return YES;
}

NSString *AQPeerSigningRequirement(AQInstallationPolicy *policy, AQPeerRole role, NSError **error) {
    if (error) *error = nil;
    if (![policy isKindOfClass:AQInstallationPolicy.class] || (role != AQPeerBroker && role != AQPeerService)) {
        AQFail(error, AQSecurityInvalidInput, @"Unknown peer role or missing policy."); return nil;
    }
    NSString *requirement = [NSString stringWithFormat:
        @"anchor apple generic and identifier \"%@\" and certificate leaf[subject.OU] = \"%@\" and cdhash H\"%@\"",
        role == AQPeerBroker ? AQBrokerID : AQServiceID, policy.teamIdentifier,
        role == AQPeerBroker ? policy.brokerCDHash : policy.serviceCDHash];
    SecRequirementRef compiled = NULL;
    OSStatus status = SecRequirementCreateWithString((__bridge CFStringRef)requirement, kSecCSDefaultFlags, &compiled);
    if (compiled) CFRelease(compiled);
    if (status != errSecSuccess) { AQFail(error, AQSecurityInvalidPolicy, @"The OS rejected the peer signing requirement."); return nil; }
    return requirement;
}

/* A descriptor's ACL is queried through the same open inode as its metadata.
 * Darwin may return NULL with ENOENT when the inode has no extended ACL, or
 * with EINVAL when an empty ACL has no first entry. Both mean empty. Any other
 * failure is an inspection failure and remains fail closed.
 */
static BOOL AQProtectedFD(int fd, BOOL directory, uid_t expectedUID, mode_t mode,
                          struct stat *metadata) {
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_uid != expectedUID || (st.st_mode & 07777) != mode ||
        (directory ? !S_ISDIR(st.st_mode) : (!S_ISREG(st.st_mode) || st.st_nlink != 1))) return NO;
    errno = 0;
    acl_t acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
    BOOL empty = acl == NULL && (errno == EINVAL || errno == ENOENT);
    if (!acl && !empty) return NO;
    acl_entry_t entry;
    if (acl) {
        BOOL valid = acl_valid(acl) == 0;
        errno = 0;
        empty = valid && acl_get_entry(acl, ACL_FIRST_ENTRY, &entry) == -1 && errno == EINVAL;
        acl_free(acl);
    }
    if (empty && metadata) *metadata = st;
    return empty;
}

/* Each open is relative to an already checked root-protected directory. Never
 * resolve a symlink, normalize a path, or reopen a checked leaf by pathname.
 */
static int AQOpenProtectedPath(NSString *path, BOOL directory, uid_t expectedUID,
                               mode_t mode, NSError **error) {
    if (![path isKindOfClass:NSString.class] || ![path hasPrefix:@"/"] || path.length < 2 ||
        [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= PATH_MAX ||
        [path rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound ||
        (directory ? (mode != 0755 && mode != 0700) : (mode != 0644 && mode != 0755))) {
        AQFail(error, AQSecurityInvalidInput, @"Protected path must be absolute and use an approved exact mode."); return -1;
    }
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    for (NSUInteger i = 1; i < parts.count; i++) {
        if ([parts[i] length] == 0 || [parts[i] isEqual:@"."] || [parts[i] isEqual:@".."]) {
            AQFail(error, AQSecurityInvalidInput, @"Protected paths cannot contain empty or relative components."); return -1;
        }
    }
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
        if (fd < 0 || !AQProtectedFD(fd, YES, 0, 0755, NULL)) {
        if (fd >= 0) close(fd);
        AQFail(error, AQSecurityUntrustedInstallation, @"Filesystem root does not satisfy installation protection."); return -1;
    }
    for (NSUInteger i = 1; i < parts.count; i++) {
        BOOL leaf = i + 1 == parts.count;
        BOOL childDirectory = !leaf || directory;
        int flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (childDirectory ? O_DIRECTORY : 0);
        int next = openat(fd, parts[i].fileSystemRepresentation, flags);
        struct stat opened, named;
        uid_t childUID = leaf ? expectedUID : 0;
        mode_t childMode = leaf ? mode : 0755;
        BOOL trusted = next >= 0 && AQProtectedFD(next, childDirectory, childUID, childMode, &opened) &&
            fstatat(fd, parts[i].fileSystemRepresentation, &named, AT_SYMLINK_NOFOLLOW) == 0 &&
            opened.st_dev == named.st_dev && opened.st_ino == named.st_ino;
        close(fd);
        if (!trusted) {
            if (next >= 0) close(next);
            AQFail(error, AQSecurityUntrustedInstallation, @"Installation ancestry, mode, ACL, inode or link count is not protected."); return -1;
        }
        fd = next;
    }
    return fd;
}

BOOL AQValidateProtectedPath(NSString *path, BOOL directory, mode_t mode, NSError **error) {
    if (error) *error = nil;
    int fd = AQOpenProtectedPath(path, directory, 0, mode, error);
    if (fd < 0) return NO;
    close(fd);
    return YES;
}

static BOOL AQEvaluateNonLoginAccountFacts(NSString *password, NSString *shell) {
    if (![password isEqual:@"*"] || ![shell isKindOfClass:NSString.class]) return NO;
    return [shell isEqual:@"/usr/bin/false"] || [shell isEqual:@"/sbin/nologin"] ||
        [shell isEqual:@"/usr/sbin/nologin"];
}

static BOOL AQValidateServiceAccountUID(uid_t uid, NSError **error) {
    char buffer[16384];
    struct passwd record;
    struct passwd *resolved = NULL;
    int lookup = getpwuid_r(uid, &record, buffer, sizeof(buffer), &resolved);
    if (lookup != 0 || !resolved || resolved->pw_uid != uid || !resolved->pw_name) {
        return AQFail(error, AQSecurityUntrustedInstallation,
            @"The pinned service UID has no usable dedicated account record.");
    }
    NSString *password = resolved->pw_passwd ? [NSString stringWithUTF8String:resolved->pw_passwd] : @"";
    NSString *shell = resolved->pw_shell ? [NSString stringWithUTF8String:resolved->pw_shell] : @"";
    if (!AQEvaluateNonLoginAccountFacts(password, shell)) {
        return AQFail(error, AQSecurityUntrustedInstallation,
            @"The pinned service identity must have no reusable password and a non-login shell.");
    }

    int groups[64];
    int groupCount = (int)(sizeof(groups) / sizeof(groups[0]));
    if (getgrouplist(resolved->pw_name, resolved->pw_gid, groups, &groupCount) != 0 ||
        groupCount != 1 || (gid_t)groups[0] != resolved->pw_gid) {
        return AQFail(error, AQSecurityUntrustedInstallation,
            @"The pinned service identity must have only its private primary group.");
    }
    return YES;
}

AQInstallationPolicy *AQLoadInstallationPolicy(NSError **error) {
    if (error) *error = nil;
    int fd = AQOpenProtectedPath(AQInstallationPath, NO, 0, 0644, error);
    if (fd < 0) return nil;
    struct stat before, after;
    uint8_t buffer[16385];
    NSUInteger count = 0;
    BOOL okay = fstat(fd, &before) == 0 && before.st_size > 0 && before.st_size <= (off_t)AQMaxPolicyBytes;
    while (okay && count < sizeof(buffer)) {
        ssize_t n = read(fd, buffer + count, sizeof(buffer) - count);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { okay = NO; break; }
        if (n == 0) break;
        count += (NSUInteger)n;
    }
    okay = okay && count == (NSUInteger)before.st_size && AQProtectedFD(fd, NO, 0, 0644, &after) &&
        before.st_dev == after.st_dev && before.st_ino == after.st_ino && before.st_size == after.st_size &&
        before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec &&
        before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec && before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec;
    close(fd);
    if (!okay) { AQFail(error, AQSecurityUntrustedInstallation, @"Installation policy is oversized, unreadable or changed during its bounded read."); return nil; }
    AQInstallationPolicy *policy = AQParseInstallationPolicy([NSData dataWithBytes:buffer length:count], error);
    if (!policy || !AQValidateServiceAccountUID(policy.serviceUID, error) ||
        !AQValidateProtectedPath(AQBrokerExecutablePath, NO, 0755, error) ||
        !AQValidateProtectedPath(AQServiceExecutablePath, NO, 0755, error)) return nil;
    policy.installedPolicy = YES;
    return policy;
}

static BOOL AQRequireInstalledPolicy(AQInstallationPolicy *policy, NSError **error) {
    if (![policy isKindOfClass:AQInstallationPolicy.class] || !policy.isInstalledPolicy)
        return AQFail(error, AQSecurityUntrustedInstallation, @"Policy was not loaded from the protected installation.");
#if defined(AQ_SECURITY_TESTING)
    if (policy.testingAuthority) return YES;
#endif
    AQInstallationPolicy *current = AQLoadInstallationPolicy(error);
    if (!current) return NO;
    if (![current.fields isEqualToDictionary:policy.fields])
        return AQFail(error, AQSecurityUntrustedInstallation, @"Installed policy changed; start a new authenticated session.");
    return YES;
}

BOOL AQAuthenticatedPeerAPIsAvailable(NSError **error) {
    if (error) *error = nil;
    if (@available(macOS 12.0, *)) {
#if defined(AQ_SECURITY_TESTING)
        if (AQTestPeerAPIsForcedUnavailable) {
            return AQFail(error, AQSecurityUnsupportedPlatform,
                @"Authenticated XPC peer APIs are unavailable in the disposable test environment.");
        }
#endif
        AQResolveAuthenticatedPeerAPIs();
        if (AQSetPeerCodeSigningRequirement && AQCreateSecCodeWithXPCMessage) return YES;
        return AQFail(error, AQSecurityUnsupportedPlatform,
            @"The runtime does not expose every authenticated XPC peer API required by this build.");
    }
    return AQFail(error, AQSecurityUnsupportedPlatform,
        @"Authenticated XPC peer requirements require macOS 12.0 or later.");
}

BOOL AQValidateNonLoginServiceIdentity(AQInstallationPolicy *policy, NSError **error) {
    if (error) *error = nil;
    if (!AQRequireInstalledPolicy(policy, error)) return NO;
    return AQValidateServiceAccountUID(policy.serviceUID, error);
}

int AQOpenProductionStagingRoot(AQInstallationPolicy *policy, NSError **error) {
    if (error) *error = nil;
    if (!AQRequireInstalledPolicy(policy, error)) return -1;
    if (!AQValidateServiceAccountUID(policy.serviceUID, error)) return -1;
    return AQOpenProtectedPath(AQProductionStagingRoot, YES, policy.serviceUID, 0700, error);
}

BOOL AQConfigurePeerRequirement(xpc_connection_t connection, AQInstallationPolicy *policy, AQPeerRole role, NSError **error) {
    if (error) *error = nil;
    if (!AQAuthenticatedPeerAPIsAvailable(error)) return NO;
    if (!AQRequireInstalledPolicy(policy, error)) return NO;
    if (!connection || xpc_get_type(connection) != XPC_TYPE_CONNECTION)
        return AQFail(error, AQSecurityInvalidInput, @"Expected a new inactive XPC connection.");
    NSString *requirement = AQPeerSigningRequirement(policy, role, error);
    if (!requirement) return NO;
    if (!AQSetPeerCodeSigningRequirement ||
        AQSetPeerCodeSigningRequirement(connection, requirement.UTF8String) != 0)
        return AQFail(error, AQSecurityUntrustedPeer, @"XPC refused the peer signing requirement.");
    return YES;
}

static BOOL AQValidateLiveCode(SecCodeRef code, AQInstallationPolicy *policy, AQPeerRole role, NSError **error) {
    NSString *requirementText = AQPeerSigningRequirement(policy, role, error);
    if (!requirementText) return NO;
    SecRequirementRef requirement = NULL;
    OSStatus status = SecRequirementCreateWithString((__bridge CFStringRef)requirementText, 0, &requirement);
    if (status == errSecSuccess) status = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);
    SecStaticCodeRef staticCode = NULL;
    if (status == errSecSuccess) status = SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode);
    if (status == errSecSuccess) status = SecStaticCodeCheckValidity(staticCode,
        kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode, requirement);
    if (staticCode) CFRelease(staticCode);
    if (requirement) CFRelease(requirement);
    if (status != errSecSuccess)
        return AQFail(error, AQSecurityUntrustedPeer, @"OS code-signature validation rejected the live executable.");
    CFDictionaryRef copied = NULL;
    status = SecCodeCopySigningInformation((SecStaticCodeRef)code, kSecCSSigningInformation | kSecCSDynamicInformation, &copied);
    NSDictionary *info = CFBridgingRelease(copied);
    if (status != errSecSuccess || !info)
        return AQFail(error, AQSecurityUntrustedPeer, @"OS code-signature information is unavailable.");
    if (!AQEvaluatePeerCodeFacts(info, policy, role, error)) return NO;
    NSString *path = nil;
    if (!AQCopyPeerExecutablePath(info, &path, error)) return NO;
    return AQValidateProtectedPath(path, NO, 0755, error);
}

BOOL AQValidatePeerMessage(xpc_object_t message, AQInstallationPolicy *policy, AQPeerRole role, NSError **error) {
    if (error) *error = nil;
    if (!AQAuthenticatedPeerAPIsAvailable(error)) return NO;
    if (!message || xpc_get_type(message) != XPC_TYPE_DICTIONARY)
        return AQFail(error, AQSecurityUntrustedPeer, @"Expected a received XPC dictionary.");
    if (!AQCreateSecCodeWithXPCMessage)
        return AQFail(error, AQSecurityUnsupportedPlatform,
            @"The runtime does not expose SecCodeCreateWithXPCMessage.");
    SecCodeRef code = NULL;
    OSStatus status = AQCreateSecCodeWithXPCMessage(message, kSecCSDefaultFlags, &code);
    if (status != errSecSuccess || !code) {
        if (code) CFRelease(code);
        return AQFail(error, AQSecurityUntrustedPeer, @"Message has no authenticated live peer code.");
    }
    BOOL valid = AQRequireInstalledPolicy(policy, error) && AQValidateLiveCode(code, policy, role, error);
    CFRelease(code);
    if (!valid) return NO;
    xpc_connection_t remote = xpc_dictionary_get_remote_connection(message);
    uid_t expected = role == AQPeerBroker ? policy.ownerUID : policy.serviceUID;
    if (!remote || xpc_connection_get_euid(remote) != expected)
        return AQFail(error, AQSecurityUntrustedPeer, @"Live peer does not have its installed execution identity.");
    return YES;
}

static BOOL AQEnvelopeBounded(NSData *envelope, NSError **error) {
    if (![envelope isKindOfClass:NSData.class] || envelope.length == 0 || envelope.length > AQMaxEnvelopeBytes)
        return AQFail(error, AQSecurityInvalidInput, @"Canonical operation envelope must contain 1..65536 bytes.");
    return YES;
}

BOOL AQVerifyOwnerSignature(AQInstallationPolicy *policy, NSData *envelope, NSData *signature, NSError **error) {
    if (error) *error = nil;
    if (!AQEnvelopeBounded(envelope, error)) return NO;
    if (![signature isKindOfClass:NSData.class] || signature.length < 8 || signature.length > 72)
        return AQFail(error, AQSecurityInvalidSignature, @"Expected a bounded DER-encoded P-256 signature.");
    if (!AQRequireInstalledPolicy(policy, error)) return NO;
    if (!policy.ownerPublicKey) return AQFail(error, AQSecurityNotEnrolled, @"No owner public key is enrolled in installation policy.");
    SecKeyRef publicKey = AQCreatePublicKey(policy.ownerPublicKey);
    BOOL verified = publicKey && SecKeyVerifySignature(publicKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)[envelope copy], (__bridge CFDataRef)[signature copy], NULL);
    if (publicKey) CFRelease(publicKey);
    return verified ? YES : AQFail(error, AQSecurityInvalidSignature, @"Signature does not match the installed owner key and exact envelope bytes.");
}

static SecAccessControlRef AQCreateOwnerAccessControl(void) CF_RETURNS_RETAINED {
    return SecAccessControlCreateWithFlags(NULL, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlUserPresence | kSecAccessControlPrivateKeyUsage, NULL);
}

/* This predicate is also used by nonprivileged unit tests with synthetic
 * attribute dictionaries. Only the caller that actually queried the Data
 * Protection keychain can establish where the attributes came from.
 */
static BOOL AQEvaluateOwnerKeyAttributes(NSDictionary *attributes, AQInstallationPolicy *policy, NSError **error) {
    if (error) *error = nil;
    if (![attributes isKindOfClass:NSDictionary.class] || !policy)
        return AQFail(error, AQSecurityKeyRejected, @"Owner key attributes are unavailable.");
    id access = attributes[(__bridge id)kSecAttrAccessControl];
    SecAccessControlRef expected = AQCreateOwnerAccessControl();
    BOOL valid = expected && access && CFGetTypeID((__bridge CFTypeRef)access) == SecAccessControlGetTypeID() &&
        CFEqual((__bridge CFTypeRef)access, expected) &&
        [attributes[(__bridge id)kSecAttrKeyType] isEqual:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom] &&
        [attributes[(__bridge id)kSecAttrKeyClass] isEqual:(__bridge id)kSecAttrKeyClassPrivate] &&
        AQUnsignedInteger(attributes[(__bridge id)kSecAttrKeySizeInBits], 256, 256) &&
        [attributes[(__bridge id)kSecAttrTokenID] isEqual:(__bridge id)kSecAttrTokenIDSecureEnclave] &&
        [attributes[(__bridge id)kSecAttrAccessGroup] isEqual:policy.keyAccessGroup] &&
        [attributes[(__bridge id)kSecAttrApplicationTag] isEqual:[policy.keyTag dataUsingEncoding:NSUTF8StringEncoding]];
    id synchronized = attributes[(__bridge id)kSecAttrSynchronizable];
    valid = valid && (!synchronized ||
        (CFGetTypeID((__bridge CFTypeRef)synchronized) == CFBooleanGetTypeID() && ![synchronized boolValue]));
    if (expected) CFRelease(expected);
    return valid ? YES : AQFail(error, AQSecurityKeyRejected, @"Actual owner key token, access group, tag or access control is not approved.");
}

static BOOL AQValidateBrokerSelf(AQInstallationPolicy *policy, NSError **error) {
    if (!AQRequireInstalledPolicy(policy, error)) return NO;
    struct stat console;
    if (getuid() != policy.ownerUID || geteuid() != policy.ownerUID ||
        lstat("/dev/console", &console) != 0 || !S_ISCHR(console.st_mode) || console.st_uid != policy.ownerUID)
        return AQFail(error, AQSecurityOwnerConsentDenied, @"Only the installed interactive console owner may use owner consent.");
    SecCodeRef selfCode = NULL;
    OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &selfCode);
    if (status != errSecSuccess || !selfCode) {
        if (selfCode) CFRelease(selfCode);
        return AQFail(error, AQSecurityUntrustedPeer, @"Cannot inspect the running broker's code identity.");
    }
    BOOL valid = AQValidateLiveCode(selfCode, policy, AQPeerBroker, error);
    CFRelease(selfCode);
    return valid;
}

static NSMutableDictionary *AQOwnerKeyQuery(AQInstallationPolicy *policy, LAContext *context) {
    NSData *keyTag = [policy.keyTag dataUsingEncoding:NSUTF8StringEncoding];
    if (keyTag == nil) return nil;
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassKey,
        (__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecAttrApplicationTag:keyTag,
        (__bridge id)kSecAttrAccessGroup:policy.keyAccessGroup,
        (__bridge id)kSecUseDataProtectionKeychain:@YES,
        (__bridge id)kSecUseAuthenticationContext:context,
        (__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne} mutableCopy];
}

static NSData *AQPublicKeyBytes(SecKeyRef privateKey) {
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (!publicKey) return nil;
    NSData *bytes = CFBridgingRelease(SecKeyCopyExternalRepresentation(publicKey, NULL));
    CFRelease(publicKey);
    return bytes;
}

/* Authentication is forbidden while obtaining/inspecting the reference. Only
 * the subsequent private-key operation may invoke user presence, with the
 * fresh context already associated by this query. No legacy keychain is used.
 */
static SecKeyRef AQCopyEnrolledKey(AQInstallationPolicy *policy, LAContext *context,
                                  NSData *expectedPublicKey, NSError **error) CF_RETURNS_RETAINED {
    NSMutableDictionary *query = AQOwnerKeyQuery(policy, context);
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecReturnRef] = @YES;
    context.interactionNotAllowed = YES;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSDictionary *attributes = CFBridgingRelease(result);
    if (status != errSecSuccess || ![attributes isKindOfClass:NSDictionary.class]) {
        AQFail(error, status == errSecItemNotFound ? AQSecurityNotEnrolled : AQSecurityKeyRejected,
            @"The enrolled Data Protection keychain item is unavailable without preliminary authentication."); return NULL;
    }
    if (!AQEvaluateOwnerKeyAttributes(attributes, policy, error)) return NULL;
    id value = attributes[(__bridge id)kSecValueRef];
    if (!value || CFGetTypeID((__bridge CFTypeRef)value) != SecKeyGetTypeID()) {
        AQFail(error, AQSecurityKeyRejected, @"The keychain did not return a private-key reference."); return NULL;
    }
    SecKeyRef key = (__bridge SecKeyRef)value;
    NSDictionary *keyAttributes = CFBridgingRelease(SecKeyCopyAttributes(key));
    if (![keyAttributes[(__bridge id)kSecAttrTokenID] isEqual:(__bridge id)kSecAttrTokenIDSecureEnclave] ||
        ![keyAttributes[(__bridge id)kSecAttrKeyType] isEqual:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom] ||
        !AQUnsignedInteger(keyAttributes[(__bridge id)kSecAttrKeySizeInBits], 256, 256) ||
        ![AQPublicKeyBytes(key) isEqual:expectedPublicKey] ||
        !SecKeyIsAlgorithmSupported(key, kSecKeyOperationTypeSign, kSecKeyAlgorithmECDSASignatureMessageX962SHA256)) {
        AQFail(error, AQSecurityKeyRejected, @"Actual Secure Enclave key does not match its installed public-key pin."); return NULL;
    }
    return (SecKeyRef)CFRetain(key);
}

/* Preserve an exact, inert display of every byte. Escaped ASCII prevents
 * controls and bidirectional Unicode from changing the apparent operation;
 * the complete hex view also exposes whitespace and invisible bytes.
 */
static NSString *AQEnvelopeDisplay(NSData *envelope) {
    const uint8_t *bytes = envelope.bytes;
    NSMutableString *text = [NSMutableString stringWithFormat:@"Operation envelope (%lu bytes)\n\nEscaped byte text:\n", (unsigned long)envelope.length];
    for (NSUInteger i = 0; i < envelope.length; i++) {
        uint8_t c = bytes[i];
        if (c >= 32 && c <= 126 && c != '\\') [text appendFormat:@"%c", c];
        else if (c == '\\') [text appendString:@"\\\\"];
        else [text appendFormat:@"\\x%02x", c];
    }
    [text appendString:@"\n\nExact bytes (hexadecimal):\n"];
    for (NSUInteger i = 0; i < envelope.length; i++) {
        [text appendFormat:@"%02x%@", bytes[i], (i + 1) % 32 == 0 ? @"\n" : @" "];
    }
    return text;
}

static BOOL AQShowApproval(NSString *title, NSString *explanation, NSString *details, NSString *approve) {
    /* This helper is a C function, so NSAssert would expand with an invalid
     * _cmd reference. Refuse off-main callers; AppKit modal UI is main-only. */
    if (!NSThread.isMainThread) return NO;
    [NSApplication sharedApplication];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = explanation;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:approve];
    alert.buttons[0].keyEquivalent = @"\r";
    alert.buttons[1].keyEquivalent = @"";
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 720, 360)];
    scroll.hasVerticalScroller = YES;
    NSTextView *view = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    view.editable = NO;
    view.selectable = YES;
    view.richText = NO;
    view.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    view.string = details;
    view.verticallyResizable = YES;
    view.horizontallyResizable = NO;
    view.textContainer.widthTracksTextView = YES;
    view.autoresizingMask = NSViewWidthSizable;
    scroll.documentView = view;
    alert.accessoryView = scroll;
    [NSApp activateIgnoringOtherApps:YES];
    return [alert runModal] == NSAlertSecondButtonReturn;
}

static LAContext *AQFreshContext(NSString *reason) {
    LAContext *context = [[LAContext alloc] init];
    context.touchIDAuthenticationAllowableReuseDuration = 0;
    context.localizedReason = reason;
    return context;
}

static dispatch_queue_t AQOwnerKeyQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.argusromtoolkit.fixture-staging.owner-key", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

/* Accessed on the main queue only. Prevent nested dialogs or overlapping
 * authentication contexts within one broker process. */
static BOOL AQConsentInFlight;
static void AQCompleteConsent(LAContext *context, BOOL ownsConsentSlot, AQSecurityCompletion completion,
                              NSData *result, NSError *error) {
    [context invalidate];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ownsConsentSlot) AQConsentInFlight = NO;
        completion(result, error);
    });
}

void AQRequestOwnerSignature(AQInstallationPolicy *policy, NSData *canonicalEnvelope, AQSecurityCompletion completion) {
    if (!completion) return;
    NSError *inputError = nil;
    BOOL bounded = AQEnvelopeBounded(canonicalEnvelope, &inputError);
    NSData *envelope = bounded ? [canonicalEnvelope copy] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error = inputError;
        if (!envelope || !AQValidateBrokerSelf(policy, &error)) {
            AQCompleteConsent(nil, NO, completion, nil, error); return;
        }
        if (!policy.ownerPublicKey) {
            AQFail(&error, AQSecurityNotEnrolled, @"Explicit owner-key enrollment is required before signing.");
            AQCompleteConsent(nil, NO, completion, nil, error); return;
        }
        if (AQConsentInFlight) {
            AQFail(&error, AQSecurityOwnerConsentDenied, @"Another owner-consent operation is in progress.");
            AQCompleteConsent(nil, NO, completion, nil, error); return;
        }
        AQConsentInFlight = YES;
        if (!AQShowApproval(@"Approve fixture staging operation",
            @"Review the complete operation below. Approval applies only to these exact bytes and requires fresh owner authentication.",
            AQEnvelopeDisplay(envelope), @"Approve operation")) {
            AQFail(&error, AQSecurityOwnerConsentDenied, @"Owner declined the displayed operation.");
            AQCompleteConsent(nil, YES, completion, nil, error); return;
        }
        LAContext *context = AQFreshContext(@"Approve the displayed fixture staging operation");
        dispatch_async(AQOwnerKeyQueue(), ^{
            @autoreleasepool {
                NSError *failure = nil;
                NSData *signature = nil;
                SecKeyRef key = NULL;
                @try {
                    if (AQValidateBrokerSelf(policy, &failure)) key = AQCopyEnrolledKey(policy, context, policy.ownerPublicKey, &failure);
                    if (key) {
                        context.interactionNotAllowed = NO;
                        signature = CFBridgingRelease(SecKeyCreateSignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                            (__bridge CFDataRef)envelope, NULL));
                        if (!signature) AQFail(&failure, AQSecurityOwnerConsentDenied, @"The Secure Enclave did not authorize this signature.");
                        else if (!AQValidateBrokerSelf(policy, &failure) || !AQVerifyOwnerSignature(policy, envelope, signature, &failure)) signature = nil;
                    }
                } @finally {
                    if (key) CFRelease(key);
                    AQCompleteConsent(context, YES, completion, signature, failure);
                }
            }
        });
    });
}

static NSData *AQCreateOwnerKey(AQInstallationPolicy *policy, LAContext *context, NSError **error) {
    if (!AQValidateBrokerSelf(policy, error)) return nil;
    NSMutableDictionary *query = AQOwnerKeyQuery(policy, context);
    if (query == nil) {
        AQFail(error, AQSecurityKeyRejected, @"Cannot encode the owner-key application tag.");
        return nil;
    }
    query[(__bridge id)kSecReturnAttributes] = @YES;
    context.interactionNotAllowed = YES;
    CFTypeRef existing = NULL;
    OSStatus found = SecItemCopyMatching((__bridge CFDictionaryRef)query, &existing);
    if (existing) CFRelease(existing);
    if (found != errSecItemNotFound) {
        AQFail(error, AQSecurityKeyRejected, @"Enrollment requires no existing key; retained or inaccessible key state needs separate owner review."); return nil;
    }
    SecAccessControlRef access = AQCreateOwnerAccessControl();
    if (!access) { AQFail(error, AQSecurityKeyRejected, @"Cannot construct the required owner-key access control."); return nil; }
    context.interactionNotAllowed = NO;
    NSData *keyTag = [policy.keyTag dataUsingEncoding:NSUTF8StringEncoding];
    if (keyTag == nil) {
        CFRelease(access);
        AQFail(error, AQSecurityKeyRejected, @"Cannot encode the owner-key application tag.");
        return nil;
    }
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits:@256,
        (__bridge id)kSecAttrTokenID:(__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecUseDataProtectionKeychain:@YES,
        (__bridge id)kSecUseAuthenticationContext:context,
        (__bridge id)kSecPrivateKeyAttrs:@{
            (__bridge id)kSecAttrIsPermanent:@YES,
            (__bridge id)kSecAttrAccessGroup:policy.keyAccessGroup,
            (__bridge id)kSecAttrApplicationTag:keyTag,
            (__bridge id)kSecAttrAccessControl:(__bridge id)access}};
    SecKeyRef generated = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, NULL);
    CFRelease(access);
    if (!generated) { AQFail(error, AQSecurityKeyRejected, @"Secure Enclave enrollment failed; no alternate key will be created."); return nil; }
    NSData *publicBytes = AQPublicKeyBytes(generated);
    CFRelease(generated);
    SecKeyRef readback = publicBytes ? AQCopyEnrolledKey(policy, context, publicBytes, error) : NULL;
    if (!readback) {
        if (error && !*error) AQFail(error, AQSecurityKeyRejected, @"Created key could not be verified; retain partial enrollment for owner review.");
        return nil;
    }
    /* The enrollment proof is internal, domain-separated random data. It is
     * never returned as an operation signature and cannot authorize staging. */
    uint8_t random[32];
    NSData *proofSignature = nil;
    NSMutableData *proof = [[@"Argus owner-key enrollment verification v1\0" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(random), random) == errSecSuccess) {
        [proof appendBytes:random length:sizeof(random)];
        context.interactionNotAllowed = NO;
        proofSignature = CFBridgingRelease(SecKeyCreateSignature(readback, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            (__bridge CFDataRef)proof, NULL));
    }
    CFRelease(readback);
    SecKeyRef publicKey = AQCreatePublicKey(publicBytes);
    BOOL valid = publicKey && proofSignature && SecKeyVerifySignature(publicKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)proof, (__bridge CFDataRef)proofSignature, NULL);
    if (publicKey) CFRelease(publicKey);
    if (!valid || !AQValidateBrokerSelf(policy, error)) {
        if (error && !*error) AQFail(error, AQSecurityKeyRejected, @"Created key failed its signing proof; retain partial enrollment for owner review.");
        return nil;
    }
    return publicBytes;
}

void AQEnrollOwnerKey(AQInstallationPolicy *policy, AQSecurityCompletion completion) {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error = nil;
        if (!AQValidateBrokerSelf(policy, &error)) { AQCompleteConsent(nil, NO, completion, nil, error); return; }
        if (policy.ownerPublicKey || AQConsentInFlight) {
            AQFail(&error, AQSecurityOwnerConsentDenied, @"Enrollment requires an unenrolled policy and no other consent operation.");
            AQCompleteConsent(nil, NO, completion, nil, error); return;
        }
        AQConsentInFlight = YES;
        NSString *details = [NSString stringWithFormat:
            @"Create one non-exportable Secure Enclave P-256 owner-consent key.\n\nOwner UID: %u\nSigning team: %@\nBroker revision: %@\nAccess group: %@\nKey tag: %@\n\nEvery future operation requires its own displayed-envelope approval and fresh owner presence. This step does not authorize fixture mutation. Installation policy must be pinned separately.",
            policy.ownerUID, policy.teamIdentifier, policy.brokerCDHash, policy.keyAccessGroup, policy.keyTag];
        if (!AQShowApproval(@"Enroll fixture staging owner key",
            @"This separate setup action creates a permanent key only after fresh owner authentication.", details, @"Approve enrollment")) {
            AQFail(&error, AQSecurityOwnerConsentDenied, @"Owner declined key enrollment.");
            AQCompleteConsent(nil, YES, completion, nil, error); return;
        }
        LAContext *context = AQFreshContext(@"Approve creation of the fixture staging owner-consent key");
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication localizedReason:context.localizedReason reply:^(BOOL success, NSError *authenticationError) {
            if (!success) {
                /* Preserve a fixed, non-attacker-controlled result. LocalAuthentication
                 * diagnostics remain local to the consent boundary. */
                (void)authenticationError;
                NSError *failure = nil;
                AQFail(&failure, AQSecurityOwnerConsentDenied, @"Fresh owner authentication did not approve enrollment.");
                AQCompleteConsent(context, YES, completion, nil, failure); return;
            }
            dispatch_async(AQOwnerKeyQueue(), ^{
                @autoreleasepool {
                    NSError *failure = nil;
                    NSData *publicKey = nil;
                    @try { publicKey = AQCreateOwnerKey(policy, context, &failure); }
                    @finally { AQCompleteConsent(context, YES, completion, publicKey, failure); }
                }
            });
        }];
    });
}

#if defined(AQ_SECURITY_TESTING)
BOOL AQSecurityTestTrustPolicy(AQInstallationPolicy *policy) {
    if (![policy isKindOfClass:AQInstallationPolicy.class]) return NO;
    policy.installedPolicy = YES;
    policy.testingAuthority = YES;
    return YES;
}

BOOL AQSecurityTestEvaluatePeerCodeFacts(NSDictionary *info, AQInstallationPolicy *policy,
                                         AQPeerRole role, NSError **error) {
    return AQEvaluatePeerCodeFacts(info, policy, role, error);
}

BOOL AQSecurityTestCopyPeerExecutablePath(NSDictionary *info, NSString **path, NSError **error) {
    return AQCopyPeerExecutablePath(info, path, error);
}

BOOL AQSecurityTestEvaluateOwnerKeyAttributes(NSDictionary *attributes,
                                              AQInstallationPolicy *policy,
                                              NSError **error) {
    return AQEvaluateOwnerKeyAttributes(attributes, policy, error);
}

BOOL AQSecurityTestValidateDirectoryFD(int fd, uid_t expectedUID, mode_t mode,
                                       NSError **error) {
    if (AQProtectedFD(fd, YES, expectedUID, mode, NULL)) return YES;
    return AQFail(error, AQSecurityUntrustedInstallation,
        @"Directory descriptor failed the protected namespace predicate.");
}

BOOL AQSecurityTestValidateFileFD(int fd, uid_t expectedUID, mode_t mode,
                                  NSError **error) {
    /* Exercises the same descriptor predicate used by package authentication;
     * it is test-only and cannot establish installation trust. */
    if (AQProtectedFD(fd, NO, expectedUID, mode, NULL)) return YES;
    return AQFail(error, AQSecurityUntrustedInstallation,
        @"File descriptor failed the protected installation predicate.");
}

BOOL AQSecurityTestEvaluateNonLoginAccountFacts(NSString *password, NSString *shell) {
    return AQEvaluateNonLoginAccountFacts(password, shell);
}

BOOL AQSecurityTestMessageHasLivePeer(xpc_object_t message, NSError **error) {
    if (error) *error = nil;
    if (!AQAuthenticatedPeerAPIsAvailable(error)) return NO;
    if (!message || xpc_get_type(message) != XPC_TYPE_DICTIONARY) {
        return AQFail(error, AQSecurityUntrustedPeer, @"Expected a received XPC dictionary.");
    }
    if (!AQCreateSecCodeWithXPCMessage) {
        return AQFail(error, AQSecurityUnsupportedPlatform,
            @"The runtime does not expose SecCodeCreateWithXPCMessage.");
    }
    SecCodeRef code = NULL;
    OSStatus status = AQCreateSecCodeWithXPCMessage(message, kSecCSDefaultFlags, &code);
    if (status != errSecSuccess || !code) {
        if (code) CFRelease(code);
        return AQFail(error, AQSecurityUntrustedPeer, @"Message has no live peer code identity.");
    }
    CFRelease(code);
    return YES;
}

void AQSecurityTestSetAuthenticatedPeerAPIsUnavailable(BOOL unavailable) {
    /* Pure fail-closed coverage switch. This symbol exists only in the
     * AQ_SECURITY_TESTING build and never changes production authority. */
    AQTestPeerAPIsForcedUnavailable = unavailable;
}
#endif
