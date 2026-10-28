#import "AQStore.h"
#import "AQJSON.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/acl.h>
#include <membership.h>
#include <poll.h>
#include <CommonCrypto/CommonDigest.h>
#include <dispatch/dispatch.h>

// All fixtures are synthetic. These tests never enroll an owner or claim that
// their locally constructed dictionaries have production signing authority.
@interface AQTestStoreClock : NSObject <AQStoreClock>
@property(nonatomic) uint64_t ticks;
@end
@implementation AQTestStoreClock
- (uint64_t)continuousTicks { return self.ticks; }
@end

static int failures;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "store FAIL %s:%d: %s\n", __func__, __LINE__, #x); failures++; } } while (0)
static NSString *Hash(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *value = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); ++i) [value appendFormat:@"%02x", digest[i]];
    return value;
}
static NSString *Pin(void) { return @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; }

@interface AQStoreFixture : NSObject
@property(nonatomic, strong) AQStore *store;
@property(nonatomic, strong) AQTestStoreClock *clock;
@property(nonatomic, strong) AQStoreTestHooks *hooks;
@property(nonatomic, copy) NSString *path;
@property(nonatomic) int rootFD;
@property(nonatomic) int sourceFD;
@property(nonatomic, copy) NSDictionary *manifest;
@property(nonatomic, copy) NSDictionary *authority;
@property(nonatomic, copy) NSDictionary *sourceFDs;
- (NSDictionary *)request:(NSString *)operation;
- (NSDictionary *)requestForSession:(NSString *)sessionID operation:(NSString *)operation;
- (NSDictionary *)authorityForSession:(NSString *)sessionID;
- (void)dispose;
@end

@implementation AQStoreFixture
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _rootFD = _sourceFD = -1;
    char templatePath[] = "/private/tmp/argus-store-test-XXXXXX";
    char *directory = mkdtemp(templatePath);
    if (!directory) return nil;
    _path = @(directory);
    NSString *payloadRoot = [_path stringByAppendingPathComponent:@"root"];
    if (mkdir(payloadRoot.fileSystemRepresentation, 0700)) return nil;
    _rootFD = open(payloadRoot.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    NSString *source = [_path stringByAppendingPathComponent:@"source"];
    NSData *bytes = [@"synthetic fixture\n" dataUsingEncoding:NSUTF8StringEncoding];
    int output = open(source.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    CHECK(output >= 0);
    CHECK(write(output, bytes.bytes, bytes.length) == (ssize_t)bytes.length);
    struct timespec times[2] = {{1700000000, 123456789}, {1700000010, 987654321}};
    CHECK(futimens(output, times) == 0);
    close(output);
    _sourceFD = open(source.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    _manifest = @{@"schema_version":@2, @"source_authority":@"service_protected_snapshot_v1",
        @"plan_sha256":Pin(), @"rules_sha256":Pin(), @"selected_fixture_ids":@[@"fixture"],
        @"coverage_mode":@"authorized_partial_plan",
        @"fixtures":@[@{@"fixture_id":@"fixture", @"platform":@"synthetic", @"representation":@"bin",
            @"group_id":@"group", @"identity":@"synthetic fixture", @"order":@0,
            @"entrypoint":@"game.bin", @"files":@[@{@"path":@"game.bin", @"role":@"entrypoint",
                @"size":@(bytes.length), @"sha256":Hash(bytes)}], @"companions":@[],
            @"identity_evidence":@"synthetic_expectation_v2",
            @"oracle_pin":@{@"schema_version":@1, @"oracle_ref":@"synthetic", @"revision":@"r1", @"sha256":Pin()}}]};
    _authority = @{@"session_id":@"session", @"grant_id":@"grant-session",
        @"connection_id":@"connection-session", @"epoch":@1,
        @"manifest_sha256":Pin(), @"plan_sha256":Pin(), @"rules_sha256":Pin(), @"deadline_ticks":@1000,
        @"host_reserve_bytes":@4096, @"destination_reserve_bytes":@8192,
        @"operations":@[@"stage", @"eligibility", @"export", @"cleanup"]};
    _sourceFDs = @{@"fixture/game.bin":@(_sourceFD)};
    _clock = [AQTestStoreClock new]; _clock.ticks = 1;
    _hooks = [AQStoreTestHooks new];
    NSError *error = nil;
    _store = [[AQStore alloc] initForTestingWithRootFD:_rootFD installationIdentity:Pin() clock:_clock hooks:_hooks error:&error];
    CHECK(_store != nil);
    CHECK([_store admitManifest:_manifest authority:_authority error:&error] != nil);
    if (error) fprintf(stderr, "store fixture setup: %s\n", error.localizedDescription.UTF8String);
    return self;
}
- (NSDictionary *)request:(NSString *)operation {
    return [self requestForSession:@"session" operation:operation];
}

- (NSDictionary *)requestForSession:(NSString *)sessionID operation:(NSString *)operation {
    NSDictionary *state = [_store inspectSession:sessionID];
    uint64_t sequence = [state[@"sequence"] unsignedLongLongValue] + 1;
    NSString *digest = Hash([[NSString stringWithFormat:@"%@-%@-%llu", sessionID, operation,
                              (unsigned long long)sequence]
                           dataUsingEncoding:NSUTF8StringEncoding]);
    return @{@"session_id":sessionID, @"grant_id":[@"grant-" stringByAppendingString:sessionID],
        @"connection_id":[@"connection-" stringByAppendingString:sessionID], @"epoch":@1,
             @"operation":operation, @"sequence":@(sequence), @"request_sha256":digest,
             @"expected_generation":state[@"generation"] ?: @0};
}

- (NSDictionary *)authorityForSession:(NSString *)sessionID {
    NSMutableDictionary *authority = [_authority mutableCopy];
    authority[@"session_id"] = sessionID;
    authority[@"grant_id"] = [@"grant-" stringByAppendingString:sessionID];
    authority[@"connection_id"] = [@"connection-" stringByAppendingString:sessionID];
    return [authority copy];
}
- (void)dispose {
    [_store revokeSession:@"session" reason:@"test_finished"];
    _store = nil;
    if (_sourceFD >= 0) close(_sourceFD);
    if (_rootFD >= 0) close(_rootFD);
    // Test-only teardown is allowed only under the mkdtemp directory this
    // fixture created. Production AQStore cleanup never uses recursive removal.
    if ([_path hasPrefix:@"/private/tmp/argus-store-test-"])
        [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
}
@end

static void TestRejectsUnprotectedStoreRoot(void) {
    char templatePath[] = "/private/tmp/argus-store-root-XXXXXX";
    char *directory = mkdtemp(templatePath);
    CHECK(directory != NULL);
    if (directory == NULL) return;

    int rootFD = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    CHECK(rootFD >= 0);
    if (rootFD < 0) { rmdir(directory); return; }

    AQTestStoreClock *clock = [AQTestStoreClock new];
    clock.ticks = 1;
    AQStoreTestHooks *hooks = [AQStoreTestHooks new];
    NSError *error = nil;
    CHECK(chmod(directory, 0755) == 0);
    AQStore *store = [[AQStore alloc] initForTestingWithRootFD:rootFD
        installationIdentity:Pin() clock:clock hooks:hooks error:&error];
    CHECK(store == nil);
    CHECK(error.code == AQStoreUnauthorizedRoot);
    store = nil;

    CHECK(chmod(directory, 0700) == 0);
    uuid_t qualifier;
    acl_t acl = acl_init(1);
    acl_entry_t entry = NULL;
    acl_permset_t permissions = NULL;
    BOOL prepared = acl != NULL && mbr_uid_to_uuid(geteuid(), qualifier) == 0 &&
        acl_create_entry(&acl, &entry) == 0 &&
        acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0 &&
        acl_set_qualifier(entry, qualifier) == 0 &&
        acl_get_permset(entry, &permissions) == 0 &&
        acl_add_perm(permissions, ACL_READ_DATA) == 0 &&
        acl_set_permset(entry, permissions) == 0 && acl_valid(acl) == 0;
    BOOL installed = prepared && acl_set_fd_np(rootFD, acl, ACL_TYPE_EXTENDED) == 0;
    CHECK(installed);
    if (acl != NULL) acl_free(acl);
    if (installed) {
        error = nil;
        store = [[AQStore alloc] initForTestingWithRootFD:rootFD
            installationIdentity:Pin() clock:clock hooks:hooks error:&error];
        CHECK(store == nil);
        CHECK(error.code == AQStoreUnauthorizedRoot);
        store = nil;
    }

    acl_t emptyACL = acl_init(0);
    CHECK(emptyACL != NULL);
    if (emptyACL != NULL) {
        CHECK(acl_set_fd_np(rootFD, emptyACL, ACL_TYPE_EXTENDED) == 0);
        acl_free(emptyACL);
    }
    close(rootFD);
    rmdir(directory);
}

static void TestCheckedLargeAccounting(void) {
    uint64_t total = 0;
    for (NSUInteger i = 0; i < 5000; ++i) CHECK(AQStoreAddBytes(total, 1048576, &total));
    CHECK(total == UINT64_C(5242880000));
    CHECK(!AQStoreAddBytes(UINT64_MAX, 1, &total));
    CHECK(AQStoreCapacityAllows(112, 100, 10, 12));
    CHECK(!AQStoreCapacityAllows(111, 100, 10, 12));
    CHECK(!AQStoreCapacityAllows(UINT64_MAX, UINT64_MAX, 1, 1));
}

static NSString *SnapshotPath(AQStoreFixture *fixture) {
    NSString *root = [fixture.path stringByAppendingPathComponent:@"root"];
    for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL])
        if ([entry hasPrefix:@"snapshot-"] || [entry hasPrefix:@"pending-"])
            return [root stringByAppendingPathComponent:entry];
    return nil;
}

static void TestSnapshotSealExportAndCleanup(void) {
    AQStoreFixture *f = [AQStoreFixture new]; NSError *error = nil;
    NSDictionary *stage = [f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error];
    CHECK([stage[@"state"] isEqual:@"eligible"]);
    if (error) fprintf(stderr, "stage error: %s\n", error.localizedDescription.UTF8String);
    NSString *member = [SnapshotPath(f) stringByAppendingPathComponent:@"fixture/game.bin"];
    struct stat before, sealed; CHECK(fstat(f.sourceFD, &before) == 0);
    CHECK(lstat(member.fileSystemRepresentation, &sealed) == 0);
    CHECK(sealed.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec);
    CHECK(sealed.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec);
    CHECK((sealed.st_mode & 0777) == 0400);
    CHECK(unlink([[f.path stringByAppendingPathComponent:@"source"] fileSystemRepresentation]) == 0);
    CHECK([f.store eligibilityForRequest:[f request:@"eligibility"] error:&error] != nil);
    int input = [f.store exportPipeForRequest:[f request:@"export"] error:&error];
    CHECK(input >= 0);
    if (input >= 0) {
        CHECK((fcntl(input, F_GETFL) & O_ACCMODE) == O_RDONLY);
        CHECK((fcntl(input, F_GETFL) & O_NONBLOCK) != 0);
        NSMutableData *stream = [NSMutableData data];
        char buffer[4096]; BOOL eof = NO;
        for (int i = 0; i < 200 && !eof; ++i) {
            ssize_t count = read(input, buffer, sizeof(buffer));
            if (count > 0) [stream appendBytes:buffer length:(NSUInteger)count];
            else if (count == 0) eof = YES;
            else { struct pollfd event = {input, POLLIN, 0}; poll(&event, 1, 10); }
        }
        CHECK(eof); CHECK(stream.length > 56);
        if (stream.length > 56) {
            CHECK(memcmp(stream.bytes, "AQSNAP1\n", 8) == 0);
            const unsigned char *raw = stream.bytes;
            uint64_t headerSize = 0; for (int i = 8; i < 16; ++i) headerSize = (headerSize << 8) | raw[i];
            CHECK(headerSize < stream.length - 56);
            if (headerSize < stream.length - 56) {
                NSDictionary *header = [NSJSONSerialization JSONObjectWithData:[stream subdataWithRange:NSMakeRange(16, (NSUInteger)headerSize)] options:0 error:NULL];
                CHECK([header[@"members"] count] == 1);
                CHECK([header[@"members"][0][@"path"] isEqual:@"fixture/game.bin"]);
                CHECK([header[@"members"][0][@"size"] unsignedLongLongValue] == 18);
                CHECK(memcmp(raw + stream.length - 40, "AQEND1\r\n", 8) == 0);
                NSData *prefix = [stream subdataWithRange:NSMakeRange(0, stream.length - 40)];
                unsigned char digest[32]; CC_SHA256(prefix.bytes, (CC_LONG)prefix.length, digest);
                CHECK(memcmp(digest, raw + stream.length - 32, 32) == 0);
                CHECK(memcmp(raw + 16 + headerSize, "synthetic fixture\n", 18) == 0);
            }
        }
        close(input);
    }
    NSDictionary *cleaned = [f.store cleanupRequest:[f request:@"cleanup"] error:&error];
    CHECK([cleaned[@"cleanup_complete"] boolValue]);
    CHECK(SnapshotPath(f) == nil);
    CHECK([f.store cleanupRequest:[f request:@"cleanup"] error:&error] == nil);
    [f dispose];
}

static void TestBindingReplayAndDeadline(void) {
    AQStoreFixture *f = [AQStoreFixture new]; NSError *error = nil;
    NSMutableDictionary *wrong = [[f request:@"stage"] mutableCopy]; wrong[@"connection_id"] = @"substitution";
    CHECK([f.store stageRequest:wrong sourceFDs:f.sourceFDs error:&error] == nil);
    CHECK(SnapshotPath(f) == nil);
    NSDictionary *first = [f request:@"stage"];
    CHECK([f.store stageRequest:first sourceFDs:f.sourceFDs error:&error] != nil);
    CHECK([f.store stageRequest:first sourceFDs:f.sourceFDs error:&error] == nil);
    NSMutableDictionary *stale = [[f request:@"eligibility"] mutableCopy]; stale[@"expected_generation"] = @0;
    CHECK([f.store eligibilityForRequest:stale error:&error] == nil);
    f.clock.ticks = 1000;
    CHECK([f.store eligibilityForRequest:[f request:@"eligibility"] error:&error] == nil);
    CHECK([f.store admitManifest:f.manifest authority:f.authority error:&error] == nil);
    [f dispose];
}

static void TestCapacityAndDescriptorAdmission(void) {
    AQStoreFixture *f = [AQStoreFixture new]; NSError *error = nil;
    f.hooks.availableBytes = ^NSNumber *{ return @8192; };
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] == nil);
    CHECK(SnapshotPath(f) == nil);
    [f dispose];
    f = [AQStoreFixture new];
    int writable = open([[f.path stringByAppendingPathComponent:@"source"] fileSystemRepresentation], O_RDWR);
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:@{@"fixture/game.bin":@(writable)} error:&error] == nil);
    close(writable); [f dispose];
    f = [AQStoreFixture new];
    CHECK(link([[f.path stringByAppendingPathComponent:@"source"] fileSystemRepresentation],
               [[f.path stringByAppendingPathComponent:@"alias"] fileSystemRepresentation]) == 0);
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] == nil);
    [f dispose];
}

static void TestPendingCrashAndJournalCorruption(void) {
    AQStoreFixture *f = [AQStoreFixture new]; NSError *error = nil;
    __block NSUInteger uncertainStageBoundaryCount = 0;
    f.hooks.boundary = ^BOOL(NSString *point) {
        if ([point isEqual:@"after_payload_mkdir"]) {
            uncertainStageBoundaryCount++;
            return NO;
        }
        return YES;
    };
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] == nil);
    CHECK(uncertainStageBoundaryCount == 1);
    f.store = nil;
    f.store = [[AQStore alloc] initForTestingWithRootFD:f.rootFD installationIdentity:Pin() clock:f.clock hooks:f.hooks error:&error];
    CHECK([[[f.store inspectSession:@"session"] objectForKey:@"state"] isEqual:@"blocked_retained"]);
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] == nil);
    CHECK(uncertainStageBoundaryCount == 1);
    CHECK([f.store cleanupRequest:[f request:@"cleanup"] error:&error] == nil);
    [f dispose];
    f = [AQStoreFixture new];
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] != nil);
    f.store = nil;
    NSString *root = [f.path stringByAppendingPathComponent:@"root"];
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL]
                     sortedArrayUsingSelector:@selector(compare:)];
    NSString *last = nil;
    for (NSString *name in names) if ([name hasPrefix:@".aq-record-"]) last = name;
    CHECK(last != nil);
    NSString *record = [root stringByAppendingPathComponent:last];
    CHECK(chmod(record.fileSystemRepresentation, 0600) == 0);
    int fd = open(record.fileSystemRepresentation, O_WRONLY); CHECK(fd >= 0);
    CHECK(ftruncate(fd, 3) == 0); close(fd); CHECK(chmod(record.fileSystemRepresentation, 0400) == 0);
    f.store = [[AQStore alloc] initForTestingWithRootFD:f.rootFD installationIdentity:Pin() clock:f.clock hooks:f.hooks error:&error];
    CHECK([[f.store classifyRecovery][@"state"] isEqual:@"blocked_retained"]);
    CHECK([f.store eligibilityForRequest:[f request:@"eligibility"] error:&error] == nil);
    [f dispose];
}

static void TestJournalRejectsNonDispatchSequenceAdvance(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    NSError *error = nil;
    CHECK([f.store stageRequest:[f request:@"stage"]
                      sourceFDs:f.sourceFDs error:&error] != nil);
    f.store = nil;

    NSString *root = [f.path stringByAppendingPathComponent:@"root"];
    NSArray<NSString *> *names = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:root error:&error];
    names = [names sortedArrayUsingSelector:@selector(compare:)];
    BOOL rewrittenDispatch = NO;
    for (NSString *name in names) {
        if (![name hasPrefix:@".aq-record-"]) continue;
        NSString *path = [root stringByAppendingPathComponent:name];
        NSData *bytes = [NSData dataWithContentsOfFile:path];
        NSDictionary *record = AQParseJSON(bytes, &error);
        if (![record[@"event"] isEqual:@"dispatch"]) continue;
        NSMutableDictionary *forged = [record mutableCopy];
        forged[@"event"] = @"stage_intent";
        NSData *canonical = AQCanonicalJSON(forged, &error);
        CHECK(canonical != nil);
        CHECK(chmod(path.fileSystemRepresentation, 0600) == 0);
        int descriptor = open(path.fileSystemRepresentation, O_WRONLY | O_TRUNC);
        CHECK(descriptor >= 0);
        if (descriptor >= 0) {
            CHECK(write(descriptor, canonical.bytes, canonical.length) ==
                  (ssize_t)canonical.length);
            CHECK(fchmod(descriptor, 0400) == 0);
            CHECK(close(descriptor) == 0);
        }
        rewrittenDispatch = YES;
        break;
    }
    CHECK(rewrittenDispatch);

    f.store = [[AQStore alloc] initForTestingWithRootFD:f.rootFD
        installationIdentity:Pin() clock:f.clock hooks:f.hooks error:&error];
    CHECK(f.store != nil);
    NSDictionary *recovery = [f.store classifyRecovery];
    CHECK([recovery[@"reason"] isEqual:@"journal_transition"]);
    [f dispose];
}

static void TestReplayFreezesAdmissionPolicyFields(void) {
    NSArray<NSString *> *fields = @[
        @"operations", @"host_reserve_bytes", @"destination_reserve_bytes"
    ];
    for (NSString *field in fields) {
        AQStoreFixture *f = [AQStoreFixture new];
        NSError *error = nil;
        CHECK([f.store stageRequest:[f request:@"stage"]
                          sourceFDs:f.sourceFDs error:&error] != nil);
        f.store = nil;

        NSString *root = [f.path stringByAppendingPathComponent:@"root"];
        NSArray<NSString *> *names = [[[NSFileManager defaultManager]
            contentsOfDirectoryAtPath:root error:&error]
            sortedArrayUsingSelector:@selector(compare:)];
        BOOL changedPolicy = NO;
        for (NSString *name in names) {
            if (![name hasPrefix:@".aq-record-"]) continue;
            NSString *path = [root stringByAppendingPathComponent:name];
            NSData *bytes = [NSData dataWithContentsOfFile:path];
            NSDictionary *record = AQParseJSON(bytes, &error);
            if (![record[@"event"] isEqual:@"dispatch"]) continue;

            NSMutableDictionary *forged = [record mutableCopy];
            NSMutableDictionary *session = [record[@"session"] mutableCopy];
            if ([field isEqual:@"operations"]) {
                session[field] = @[@"stage"];
            } else {
                session[field] = @1;
            }
            forged[@"session"] = session;
            NSData *canonical = AQCanonicalJSON(forged, &error);
            CHECK(canonical != nil);
            CHECK(chmod(path.fileSystemRepresentation, 0600) == 0);
            int descriptor = open(path.fileSystemRepresentation, O_WRONLY | O_TRUNC);
            CHECK(descriptor >= 0);
            if (descriptor >= 0) {
                CHECK(write(descriptor, canonical.bytes, canonical.length) ==
                      (ssize_t)canonical.length);
                CHECK(fchmod(descriptor, 0400) == 0);
                CHECK(close(descriptor) == 0);
            }
            changedPolicy = YES;
            break;
        }
        CHECK(changedPolicy);
        f.store = [[AQStore alloc] initForTestingWithRootFD:f.rootFD
            installationIdentity:Pin() clock:f.clock hooks:f.hooks error:&error];
        NSDictionary *recovery = [f.store classifyRecovery];
        CHECK([recovery[@"state"] isEqual:@"blocked_retained"]);
        CHECK([recovery[@"reason"] isEqual:@"journal_transition"]);
        [f dispose];
    }
}

static void TestForeignCleanupAndUncertainUnlink(void) {
    AQStoreFixture *f = [AQStoreFixture new]; NSError *error = nil;
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] != nil);
    NSString *foreign = [SnapshotPath(f) stringByAppendingPathComponent:@"foreign"];
    int fd = open(foreign.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600); CHECK(fd >= 0); close(fd);
    CHECK([f.store cleanupRequest:[f request:@"cleanup"] error:&error] == nil);
    CHECK(access(foreign.fileSystemRepresentation, F_OK) == 0);
    CHECK(access([[SnapshotPath(f) stringByAppendingPathComponent:@"fixture/game.bin"] fileSystemRepresentation], F_OK) == 0);
    [f dispose];
    f = [AQStoreFixture new];
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] != nil);
    f.hooks.boundary = ^BOOL(NSString *point) { return ![point isEqual:@"after_unlink"]; };
    CHECK([f.store cleanupRequest:[f request:@"cleanup"] error:&error] == nil);
    f.hooks.boundary = nil;
    CHECK([f.store cleanupRequest:[f request:@"cleanup"] error:&error] == nil);
    CHECK([[[f.store inspectSession:@"session"] objectForKey:@"effect_state"] isEqual:@"uncertain"]);
    [f dispose];
}

static void TestCleanupReplacementImmediatelyBeforeUnlinkIsRetained(void) {
    AQStoreFixture *f = [AQStoreFixture new]; NSError *error = nil;
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] != nil);
    NSString *member = [SnapshotPath(f) stringByAppendingPathComponent:@"fixture/game.bin"];
    __block BOOL replaced = NO;
    f.hooks.boundary = ^BOOL(NSString *point) {
        NSString *expected = [@"before_cleanup_unlink:" stringByAppendingString:@"fixture/game.bin"];
        if (![point isEqual:expected]) return YES;
        NSString *replacement = [member stringByAppendingString:@".replacement"];
        NSData *bytes = [@"same-user replacement" dataUsingEncoding:NSUTF8StringEncoding];
        int fd = open(replacement.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
        CHECK(fd >= 0);
        if (fd >= 0) {
            CHECK(write(fd, bytes.bytes, bytes.length) == (ssize_t)bytes.length);
            CHECK(close(fd) == 0);
        }
        CHECK(rename(replacement.fileSystemRepresentation, member.fileSystemRepresentation) == 0);
        replaced = YES;
        return YES;
    };
    CHECK([f.store cleanupRequest:[f request:@"cleanup"] error:&error] == nil);
    CHECK(replaced);
    CHECK(error.code == AQStoreIntegrityFailure);
    CHECK([[[f.store inspectSession:@"session"] objectForKey:@"state"] isEqual:@"blocked_retained"]);
    CHECK([[[f.store inspectSession:@"session"] objectForKey:@"effect_state"] isEqual:@"retained"]);
    NSData *retained = [NSData dataWithContentsOfFile:member];
    const char expectedBytes[] = "same-user replacement";
    NSData *expected = [NSData dataWithBytes:expectedBytes length:sizeof(expectedBytes) - 1];
    CHECK([retained isEqualToData:expected]);
    [f dispose];
}

static void TestExportRevocationUsesSynchronizedLiveness(void) {
    AQStoreFixture *f = [AQStoreFixture new]; NSError *error = nil;
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] != nil);
    dispatch_semaphore_t entered = dispatch_semaphore_create(0);
    dispatch_semaphore_t release = dispatch_semaphore_create(0);
    __block BOOL boundaryReached = NO;
    f.hooks.boundary = ^BOOL(NSString *point) {
        if (![point isEqual:@"before_export_member"]) return YES;
        boundaryReached = YES;
        dispatch_semaphore_signal(entered);
        dispatch_semaphore_wait(release, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        return YES;
    };
    int input = [f.store exportPipeForRequest:[f request:@"export"] error:&error];
    CHECK(input >= 0);
    long waited = dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    CHECK(waited == 0);
    CHECK(boundaryReached);
    [f.store revokeSession:@"session" reason:@"concurrent_revocation"];
    dispatch_semaphore_signal(release);
    if (input >= 0) {
        char buffer[4096];
        for (int i = 0; i < 200; ++i) {
            ssize_t count = read(input, buffer, sizeof(buffer));
            if (count == 0) break;
            if (count < 0) {
                struct pollfd event = {input, POLLIN, 0};
                poll(&event, 1, 10);
            }
        }
        close(input);
    }
    NSDictionary *state = [f.store inspectSession:@"session"];
    CHECK([state[@"revoked"] boolValue]);
    CHECK([state[@"state"] isEqual:@"revoked"]);
    CHECK([state[@"effect_state"] isEqual:@"retained"]);
    [f dispose];
}

static void TestRevocationAndPostWriteDeadline(void) {
    AQStoreFixture *f = [AQStoreFixture new]; NSError *error = nil;
    __weak AQStoreFixture *weakFixture = f;
    f.hooks.boundary = ^BOOL(NSString *point) {
        if ([point isEqual:@"after_copy_chunk"]) [weakFixture.store revokeSession:@"session" reason:@"connection_lost"];
        return YES;
    };
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] == nil);
    CHECK([[f.store inspectSession:@"session"][@"revoked"] boolValue]);
    [f dispose];
    f = [AQStoreFixture new]; weakFixture = f;
    f.hooks.boundary = ^BOOL(NSString *point) {
        if ([point isEqual:@"before_publish"]) weakFixture.clock.ticks = 1000;
        return YES;
    };
    CHECK([f.store stageRequest:[f request:@"stage"] sourceFDs:f.sourceFDs error:&error] == nil);
    CHECK(![[[f.store inspectSession:@"session"] objectForKey:@"state"] isEqual:@"eligible"]);
    [f dispose];
}

static void TestRequestDigestReuseAtLaterSequence(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    NSError *error = nil;
    NSDictionary *stageRequest = [f request:@"stage"];
    CHECK([f.store stageRequest:stageRequest sourceFDs:f.sourceFDs error:&error] != nil);

    NSMutableDictionary *reused = [[f request:@"eligibility"] mutableCopy];
    reused[@"request_sha256"] = stageRequest[@"request_sha256"];
    CHECK([f.store eligibilityForRequest:reused error:&error] == nil);
    CHECK(error.code == AQStoreInvalidState);
    [f dispose];
}

static void TestMultipleSessionRecoveryAndFreshAdmission(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    NSError *error = nil;
    CHECK([f.store admitManifest:f.manifest authority:[f authorityForSession:@"session-b"]
        error:&error] != nil);
    CHECK([f.store stageRequest:[f requestForSession:@"session" operation:@"stage"]
        sourceFDs:f.sourceFDs error:&error] != nil);
    NSDictionary *eligibilityRequest =
        [f requestForSession:@"session" operation:@"eligibility"];
    CHECK([f.store eligibilityForRequest:eligibilityRequest error:&error] != nil);
    NSMutableDictionary *secondStage =
        [[f requestForSession:@"session-b" operation:@"stage"] mutableCopy];
    secondStage[@"request_sha256"] = eligibilityRequest[@"request_sha256"];
    CHECK([f.store stageRequest:secondStage sourceFDs:f.sourceFDs error:&error] != nil);

    f.store = nil;
    f.store = [[AQStore alloc] initForTestingWithRootFD:f.rootFD installationIdentity:Pin()
        clock:f.clock hooks:f.hooks error:&error];
    CHECK(f.store != nil);
    NSDictionary *recovery = [f.store classifyRecovery];
    CHECK([recovery[@"state"] isEqual:@"blocked_retained"]);
    CHECK([recovery[@"fresh_admission_available"] boolValue]);
    for (NSString *sessionID in @[@"session", @"session-b"]) {
        NSDictionary *recovered = [f.store inspectSession:sessionID];
        CHECK([recovered[@"state"] isEqual:@"blocked_retained"]);
        CHECK([recovered[@"generation"] unsignedLongLongValue] == 1);
    }
    CHECK([f.store stageRequest:[f requestForSession:@"session" operation:@"stage"]
        sourceFDs:f.sourceFDs error:&error] == nil);

    CHECK([f.store admitManifest:f.manifest authority:[f authorityForSession:@"session-c"]
        error:&error] != nil);
    CHECK([[f.store inspectSession:@"session-c"][@"state"] isEqual:@"admitted"]);
    CHECK([f.store stageRequest:[f requestForSession:@"session-c" operation:@"stage"]
        sourceFDs:f.sourceFDs error:&error] != nil);
    CHECK([[f.store inspectSession:@"session-c"][@"state"] isEqual:@"eligible"]);
    int exportFD = [f.store exportPipeForRequest:[f requestForSession:@"session-c" operation:@"export"]
        error:&error];
    CHECK(exportFD >= 0);
    if (exportFD >= 0) {
        NSMutableData *stream = [NSMutableData data];
        char buffer[4096]; BOOL eof = NO;
        for (int i = 0; i < 200 && !eof; ++i) {
            ssize_t count = read(exportFD, buffer, sizeof(buffer));
            if (count > 0) [stream appendBytes:buffer length:(NSUInteger)count];
            else if (count == 0) eof = YES;
            else { struct pollfd event = {exportFD, POLLIN, 0}; poll(&event, 1, 10); }
        }
        CHECK(eof);
        CHECK(stream.length > 56);
        if (stream.length > 8) CHECK(memcmp(stream.bytes, "AQSNAP1\n", 8) == 0);
        close(exportFD);
    }
    recovery = [f.store classifyRecovery];
    CHECK([recovery[@"state"] isEqual:@"blocked_retained"]);
    CHECK(![recovery[@"fresh_admission_available"] boolValue]);
    CHECK([recovery[@"sessions"] unsignedLongLongValue] == 3);
    CHECK([f.store admitManifest:f.manifest authority:[f authorityForSession:@"session-d"]
        error:&error] == nil);

    f.store = nil;
    f.store = [[AQStore alloc] initForTestingWithRootFD:f.rootFD installationIdentity:Pin()
        clock:f.clock hooks:f.hooks error:&error];
    CHECK(f.store != nil);
    recovery = [f.store classifyRecovery];
    CHECK([recovery[@"state"] isEqual:@"blocked_retained"]);
    CHECK([recovery[@"sessions"] unsignedLongLongValue] == 3);
    CHECK([recovery[@"fresh_admission_available"] boolValue]);
    for (NSString *sessionID in @[@"session", @"session-b", @"session-c"]) {
        CHECK([[f.store inspectSession:sessionID][@"state"] isEqual:@"blocked_retained"]);
    }
    CHECK([f.store stageRequest:[f requestForSession:@"session-c" operation:@"stage"]
        sourceFDs:f.sourceFDs error:&error] == nil);
    [f dispose];
}

static void TestGrantCannotBeReusedForFreshSession(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    NSError *error = nil;
    NSMutableDictionary *reused = [[f authorityForSession:@"session-fresh"] mutableCopy];
    reused[@"grant_id"] = f.authority[@"grant_id"];

    CHECK([f.store admitManifest:f.manifest authority:reused error:&error] == nil);
    CHECK(error.code == AQStoreInvalidState);
    CHECK([f.store inspectSession:@"session-fresh"] == nil);
    [f dispose];
}

static void TestGrantCannotBeReusedAfterJournalRecovery(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    NSError *error = nil;
    f.store = nil;
    f.store = [[AQStore alloc] initForTestingWithRootFD:f.rootFD
        installationIdentity:Pin() clock:f.clock hooks:f.hooks error:&error];
    CHECK(f.store != nil);
    NSMutableDictionary *reused = [[f authorityForSession:@"session-recovered"] mutableCopy];
    reused[@"grant_id"] = f.authority[@"grant_id"];
    error = nil;

    CHECK([f.store admitManifest:f.manifest authority:reused error:&error] == nil);
    CHECK(error.code == AQStoreInvalidState);
    CHECK([f.store inspectSession:@"session-recovered"] == nil);
    [f dispose];
}

static void TestConcurrentAdmissionConsumesGrantOnce(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    dispatch_semaphore_t start = dispatch_semaphore_create(0);
    dispatch_group_t admissions = dispatch_group_create();
    NSObject *resultsLock = [NSObject new];
    __block NSUInteger admittedCount = 0;
    __block NSUInteger rejectedCount = 0;
    __block NSUInteger unexpectedCount = 0;

    NSMutableDictionary *first = [[f authorityForSession:@"concurrent-a"] mutableCopy];
    NSMutableDictionary *second = [[f authorityForSession:@"concurrent-b"] mutableCopy];
    first[@"grant_id"] = @"grant-concurrent-single-use";
    second[@"grant_id"] = @"grant-concurrent-single-use";

    for (NSDictionary *authority in @[first, second]) {
        dispatch_group_async(admissions, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            dispatch_semaphore_signal(ready);
            long startWait = dispatch_semaphore_wait(start,
                dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
            NSError *error = nil;
            NSDictionary *result = startWait == 0
                ? [f.store admitManifest:f.manifest authority:authority error:&error]
                : nil;
            @synchronized (resultsLock) {
                if (result != nil) {
                    admittedCount += 1;
                } else if (startWait == 0 && error.code == AQStoreInvalidState) {
                    rejectedCount += 1;
                } else {
                    unexpectedCount += 1;
                }
            }
        });
    }

    long firstReady = dispatch_semaphore_wait(ready,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    long secondReady = dispatch_semaphore_wait(ready,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    dispatch_semaphore_signal(start);
    dispatch_semaphore_signal(start);
    long admissionsFinished = dispatch_group_wait(admissions,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    CHECK(firstReady == 0 && secondReady == 0);
    CHECK(admissionsFinished == 0);
    CHECK(admittedCount == 1);
    CHECK(rejectedCount == 1);
    CHECK(unexpectedCount == 0);
    CHECK(([f.store inspectSession:@"concurrent-a"] != nil) !=
          ([f.store inspectSession:@"concurrent-b"] != nil));
    [f dispose];
}

static void TestJournalSnapshotAndRevocationAreLinearizable(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    dispatch_semaphore_t snapshotReached = dispatch_semaphore_create(0);
    dispatch_semaphore_t continueSnapshot = dispatch_semaphore_create(0);
    dispatch_semaphore_t revocationStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t revocationFinished = dispatch_semaphore_create(0);
    dispatch_group_t operations = dispatch_group_create();
    NSMutableArray<NSDictionary *> *writtenRecords = [NSMutableArray array];
    __block BOOL pausedFirstSnapshot = NO;

    f.hooks.boundary = ^BOOL(NSString *point) {
        if ([point isEqual:@"before_record_snapshot"] && !pausedFirstSnapshot) {
            pausedFirstSnapshot = YES;
            dispatch_semaphore_signal(snapshotReached);
            dispatch_semaphore_wait(continueSnapshot, DISPATCH_TIME_FOREVER);
        }
        return YES;
    };
    f.hooks.recordWritten = ^(NSString *event, NSDictionary *session) {
        @synchronized(writtenRecords) {
            [writtenRecords addObject:@{@"event": event, @"session": session}];
        }
    };

    NSDictionary *request = [f request:@"stage"];
    dispatch_group_async(operations, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSError *error = nil;
        [f.store stageRequest:request sourceFDs:f.sourceFDs error:&error];
    });
    long snapshotWait = dispatch_semaphore_wait(snapshotReached,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    CHECK(snapshotWait == 0);

    dispatch_group_async(operations, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        dispatch_semaphore_signal(revocationStarted);
        [f.store revokeSession:@"session" reason:@"interleaving_revocation"];
        dispatch_semaphore_signal(revocationFinished);
    });
    CHECK(dispatch_semaphore_wait(revocationStarted,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    long revocationBeforeSnapshotRelease = dispatch_semaphore_wait(revocationFinished,
        dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    dispatch_semaphore_signal(continueSnapshot);
    CHECK(dispatch_group_wait(operations,
        dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0);
    CHECK(revocationBeforeSnapshotRelease != 0);

    NSUInteger dispatchIndex = NSNotFound;
    NSUInteger revokedIndex = NSNotFound;
    NSDictionary *dispatchSession = nil;
    NSDictionary *revokedSession = nil;
    @synchronized(writtenRecords) {
        for (NSUInteger index = 0; index < writtenRecords.count; index++) {
            NSDictionary *record = writtenRecords[index];
            if ([record[@"event"] isEqual:@"dispatch"]) {
                dispatchIndex = index;
                dispatchSession = record[@"session"];
            } else if ([record[@"event"] isEqual:@"revoked"]) {
                revokedIndex = index;
                revokedSession = record[@"session"];
            }
        }
    }
    CHECK(dispatchIndex != NSNotFound && revokedIndex != NSNotFound &&
          dispatchSession != nil && revokedSession != nil);
    CHECK(dispatchIndex < revokedIndex);
    CHECK(![dispatchSession[@"revoked"] boolValue]);
    CHECK([dispatchSession[@"state"] isEqual:@"admitted"]);
    CHECK([dispatchSession[@"sequence"] unsignedLongLongValue] == 1);
    CHECK([revokedSession[@"revoked"] boolValue]);
    CHECK([revokedSession[@"state"] isEqual:@"revoked"]);
    [f dispose];
}

static NSString *LongStorePath(NSUInteger index, NSUInteger length) {
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    NSUInteger remaining = length;
    NSString *directory = [@"" stringByPaddingToLength:255 withString:@"d" startingAtIndex:0];
    while (remaining > 255) {
        [components addObject:directory];
        remaining -= 256;
    }
    NSString *leaf = [NSString stringWithFormat:@"f%04lu", (unsigned long)index];
    if (remaining < leaf.length) return nil;
    [components addObject:[leaf stringByPaddingToLength:remaining withString:@"x" startingAtIndex:0]];
    return [components componentsJoinedByString:@"/"];
}

static NSUInteger ExportMetadataHeaderLength(NSString *sessionID, NSArray<NSString *> *paths) {
    NSDictionary *emptyHeader = @{@"schema_version": @1, @"session_id": sessionID,
        @"manifest_sha256": Pin(), @"generation": @0, @"members": @[]};
    NSData *emptyEncoding = AQCanonicalJSON(emptyHeader, NULL);
    if (emptyEncoding == nil) return NSUIntegerMax;
    NSUInteger length = emptyEncoding.length;
    for (NSUInteger index = 0; index < paths.count; ++index) {
        NSString *fixtureID = [NSString stringWithFormat:@"f%04lu", (unsigned long)index];
        NSDictionary *member = @{@"path": [fixtureID stringByAppendingFormat:@"/%@", paths[index]],
            @"size": @0, @"sha256": Pin()};
        NSData *memberEncoding = AQCanonicalJSON(member, NULL);
        NSUInteger separatorBytes = index == 0 ? 0 : 1;
        if (memberEncoding == nil || NSUIntegerMax - length < memberEncoding.length + separatorBytes) {
            return NSUIntegerMax;
        }
        length += memberEncoding.length + separatorBytes;
    }
    return length;
}

static NSArray<NSString *> *MetadataPathsForHeaderSize(NSString *sessionID, NSUInteger targetSize) {
    const NSUInteger fileCount = 32;
    const NSUInteger basePathLength = 1925;
    for (NSUInteger lastPathLength = basePathLength; lastPathLength <= 4096; ++lastPathLength) {
        NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:fileCount];
        BOOL validPaths = YES;
        for (NSUInteger index = 0; index < fileCount; ++index) {
            NSUInteger pathLength = index + 1 == fileCount ? lastPathLength : basePathLength;
            NSString *path = LongStorePath(index, pathLength);
            if (path == nil) { validPaths = NO; break; }
            [paths addObject:path];
        }
        if (!validPaths) continue;
        NSUInteger length = ExportMetadataHeaderLength(sessionID, paths);
        if (length == targetSize) return [paths copy];
        if (length > targetSize) {
            NSUInteger excess = length - targetSize;
            if (excess >= basePathLength) return nil;
            for (NSUInteger index = 0; index + 1 < fileCount; ++index) {
                NSMutableArray<NSString *> *adjusted = [paths mutableCopy];
                adjusted[index] = LongStorePath(index, basePathLength - excess);
                if (ExportMetadataHeaderLength(sessionID, adjusted) == targetSize) return [adjusted copy];
            }
            return nil;
        }
    }
    return nil;
}

static NSDictionary *MetadataHeavyManifest(NSArray<NSString *> *paths) {
    NSMutableArray<NSString *> *selected = [NSMutableArray arrayWithCapacity:paths.count];
    NSMutableArray<NSDictionary *> *fixtures = [NSMutableArray arrayWithCapacity:paths.count];
    for (NSUInteger index = 0; index < paths.count; ++index) {
        NSString *fixtureID = [NSString stringWithFormat:@"f%04lu", (unsigned long)index];
        NSString *groupID = [NSString stringWithFormat:@"group-%04lu", (unsigned long)index];
        NSString *path = paths[index];
        [selected addObject:fixtureID];
        [fixtures addObject:@{@"fixture_id": fixtureID, @"platform": @"synthetic",
            @"representation": @"bin", @"group_id": groupID, @"identity": @"synthetic fixture",
            @"order": @(index), @"entrypoint": path,
            @"files": @[@{@"path": path, @"role": @"entrypoint", @"size": @0, @"sha256": Pin()}],
            @"companions": @[], @"identity_evidence": @"synthetic_expectation_v2",
            @"oracle_pin": @{@"schema_version": @1, @"oracle_ref": @"synthetic",
                @"revision": @"r1", @"sha256": Pin()}}];
    }
    return @{@"schema_version": @2, @"source_authority": @"service_protected_snapshot_v1",
        @"plan_sha256": Pin(), @"rules_sha256": Pin(), @"coverage_mode": @"authorized_partial_plan",
        @"selected_fixture_ids": selected, @"fixtures": fixtures};
}

static NSUInteger OpenDescriptorCount(void) {
    NSUInteger count = 0;
    for (int descriptor = 0; descriptor < getdtablesize(); ++descriptor) {
        if (fcntl(descriptor, F_GETFD) >= 0) count++;
    }
    return count;
}

static void TestExportMetadataHeaderPreflight(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    __block NSUInteger writtenRecords = 0;
    f.hooks.recordWritten = ^(__unused NSString *event, __unused NSDictionary *session) {
        writtenRecords++;
    };

    NSString *oversizedSession = @"header-overflow";
    NSArray<NSString *> *oversizedPaths = MetadataPathsForHeaderSize(oversizedSession, 64 * 1024 + 1);
    CHECK(oversizedPaths.count == 32);
    if (oversizedPaths == nil) { [f dispose]; return; }
    NSDictionary *oversizedManifest = MetadataHeavyManifest(oversizedPaths);
    CHECK(ExportMetadataHeaderLength(oversizedSession, oversizedPaths) == 64 * 1024 + 1);
    NSError *error = nil;
    CHECK(!AQStoreExportHeaderWithinLimitForTesting(oversizedManifest, oversizedSession, Pin(), 0, &error));
    CHECK(error.code == AQStoreMetadataHeaderTooLarge);
    NSUInteger descriptorsBefore = OpenDescriptorCount();
    NSUInteger beforeRejectedAdmission = writtenRecords;
    CHECK([f.store admitManifest:oversizedManifest
        authority:[f authorityForSession:oversizedSession] error:&error] == nil);
    CHECK(writtenRecords == beforeRejectedAdmission);
    CHECK(OpenDescriptorCount() == descriptorsBefore);

    NSString *boundarySession = @"header-boundary";
    NSArray<NSString *> *boundaryPaths = MetadataPathsForHeaderSize(boundarySession, 64 * 1024);
    CHECK(boundaryPaths.count == 32);
    if (boundaryPaths == nil) { [f dispose]; return; }
    CHECK(ExportMetadataHeaderLength(boundarySession, boundaryPaths) == 64 * 1024);
    NSDictionary *boundaryManifest = MetadataHeavyManifest(boundaryPaths);
    error = nil;
    CHECK(AQStoreExportHeaderWithinLimitForTesting(boundaryManifest, boundarySession, Pin(), 0, &error));
    CHECK(error == nil);
    NSMutableArray<NSDictionary *> *boundaryMembers = [NSMutableArray arrayWithCapacity:boundaryPaths.count];
    for (NSUInteger index = 0; index < boundaryPaths.count; ++index) {
        NSString *fixtureID = [NSString stringWithFormat:@"f%04lu", (unsigned long)index];
        [boundaryMembers addObject:@{@"path": [fixtureID stringByAppendingFormat:@"/%@", boundaryPaths[index]],
            @"size": @0, @"sha256": Pin()}];
    }
    NSData *boundaryHeader = AQCanonicalJSON(@{@"schema_version": @1,
        @"session_id": boundarySession, @"manifest_sha256": Pin(),
        @"generation": @0, @"members": boundaryMembers}, NULL);
    CHECK(boundaryHeader.length == 64 * 1024);
    CHECK([f.store admitManifest:boundaryManifest
        authority:[f authorityForSession:boundarySession] error:&error] != nil);
    CHECK(writtenRecords == beforeRejectedAdmission + 1);
    CHECK(OpenDescriptorCount() == descriptorsBefore);

    f.store = nil;
    AQTestStoreClock *recoveryClock = [AQTestStoreClock new];
    recoveryClock.ticks = 1;
    AQStoreTestHooks *recoveryHooks = [AQStoreTestHooks new];
    f.store = [[AQStore alloc] initForTestingWithRootFD:f.rootFD installationIdentity:Pin()
        clock:recoveryClock hooks:recoveryHooks error:&error];
    CHECK(f.store != nil);
    NSDictionary *recovery = [f.store classifyRecovery];
    CHECK([recovery[@"state"] isEqual:@"blocked_retained"]);
    CHECK([recovery[@"reason"] isEqual:@"restart_requires_fresh_authority"]);
    CHECK([recovery[@"sessions"] unsignedLongLongValue] == 2);
    CHECK(writtenRecords == beforeRejectedAdmission + 1);
    [f dispose];
}

static void TestDispatchAppendFailureLeavesSequenceAndDigestRetryable(void) {
    AQStoreFixture *f = [AQStoreFixture new];
    NSDictionary *request = [f request:@"stage"];
    f.hooks.boundary = ^BOOL(NSString *point) {
        return ![point isEqual:@"before_record_snapshot"];
    };
    NSError *error = nil;
    CHECK([f.store stageRequest:request sourceFDs:f.sourceFDs error:&error] == nil);
    CHECK(error != nil);

    f.hooks.boundary = nil;
    error = nil;
    CHECK([f.store stageRequest:request sourceFDs:f.sourceFDs error:&error] != nil);
    CHECK(error == nil);
    NSDictionary *state = [f.store inspectSession:@"session"];
    CHECK([state[@"sequence"] unsignedLongLongValue] == 1);
    [f dispose];
}

int AQRunStoreTests(void) {
    @autoreleasepool {
        failures = 0;
        TestRejectsUnprotectedStoreRoot();
        TestCheckedLargeAccounting(); TestSnapshotSealExportAndCleanup();
        TestBindingReplayAndDeadline(); TestCapacityAndDescriptorAdmission();
        TestPendingCrashAndJournalCorruption(); TestJournalRejectsNonDispatchSequenceAdvance();
        TestReplayFreezesAdmissionPolicyFields();
        TestForeignCleanupAndUncertainUnlink();
        TestCleanupReplacementImmediatelyBeforeUnlinkIsRetained();
        TestExportRevocationUsesSynchronizedLiveness();
        TestRevocationAndPostWriteDeadline();
        TestRequestDigestReuseAtLaterSequence(); TestMultipleSessionRecoveryAndFreshAdmission();
        TestGrantCannotBeReusedForFreshSession();
        TestGrantCannotBeReusedAfterJournalRecovery();
        TestConcurrentAdmissionConsumesGrantOnce();
        TestJournalSnapshotAndRevocationAreLinearizable();
        TestExportMetadataHeaderPreflight();
        TestDispatchAppendFailureLeavesSequenceAndDigestRetryable();
        fprintf(stderr, "store tests: %d failure(s)\n", failures);
        return failures ? 1 : 0;
    }
}
#ifdef AQ_STORE_STANDALONE
int main(void) { return AQRunStoreTests(); }
#endif
