#import "AQBrokerProtocol.h"
#import "AQJSON.h"

#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#pragma clang diagnostic ignored "-Wunused-function"
#include "../broker/main.m"
#pragma clang diagnostic pop

static int brokerFailures;
static uint64_t BrokerTestDeadlineOverride;
#define BROKER_CHECK(value) do { \
    if (!(value)) { fprintf(stderr, "broker FAIL %s:%d: %s\n", __func__, __LINE__, #value); \
        brokerFailures++; } \
} while (0)

static NSString *BrokerReceiptDirectory(void) {
    static NSString *directory;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"argus-broker-receipts.%d.XXXXXX", getpid()]];
        char path[PATH_MAX] = {0};
        if (![template getFileSystemRepresentation:path maxLength:sizeof(path)] ||
            mkdtemp(path) == NULL || chmod(path, 0700) != 0) {
            directory = nil;
            return;
        }
        directory = [NSString stringWithUTF8String:path];
    });
    return directory;
}

@interface BrokerFailingResponseTransport : AQBrokerXPCTransport
@property(nonatomic, strong) NSDictionary *testResponse;
@end

@implementation BrokerFailingResponseTransport
- (NSDictionary *)exchangeRequest:(NSDictionary *)request
               serviceRequestData:(NSData *)serviceRequestData
                       sourceFDs:(NSArray<NSNumber *> *)sourceFDs
                       documents:(NSDictionary *)documents
                authorizationData:(NSData *)authorizationData
                         session:(AQBrokerSequentialSession *)session
                           token:(uint64_t *)token
                      exportFDOut:(int *)exportFD
                    outcomeKnown:(BOOL *)outcomeKnown
                           error:(NSError **)error {
    (void)serviceRequestData;
    (void)sourceFDs;
    (void)documents;
    (void)authorizationData;
    if (![session beginRequest:request token:token error:error]) return nil;
    if (![session acceptResponseForToken:*token response:self.testResponse error:error]) return nil;
    if (exportFD != NULL) *exportFD = -1;
    if (outcomeKnown != NULL) *outcomeKnown = YES;
    return self.testResponse;
}
@end

@interface BrokerReceiptQueryTransport : AQBrokerXPCTransport
@property(nonatomic, copy) NSDictionary *testReceiptReply;
@property(nonatomic, copy) NSDictionary *observedReceiptRequest;
@property(nonatomic) uint64_t observedReceiptDeadlineNanoseconds;
@end

@implementation BrokerReceiptQueryTransport
- (NSDictionary *)exchangeReceiptControl:(NSDictionary *)request
                      deadlineNanoseconds:(uint64_t)deadline
                                    error:(NSError **)error {
    self.observedReceiptRequest = [request copy];
    self.observedReceiptDeadlineNanoseconds = deadline;
    if (error != NULL) *error = nil;
    return self.testReceiptReply;
}
@end

static NSString *BrokerDigest(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); ++index) [text appendFormat:@"%02x", digest[index]];
    return text;
}

/** Creates a 0600 file only when no directory entry currently occupies the
 * pathname, then writes the complete fixture before closing it. */
static BOOL BrokerCreateForeignFile(NSString *path, NSData *bytes) {
    int fd = open(path.fileSystemRepresentation,
                  O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (fd < 0) return NO;
    BOOL wrote = AQBrokerWriteAll(fd, bytes, NULL);
    BOOL closed = close(fd) == 0;
    if (!wrote || !closed) {
        (void)unlink(path.fileSystemRepresentation);
        return NO;
    }
    return YES;
}

static NSData *BrokerReadFile(NSString *path) {
    return [NSData dataWithContentsOfFile:path];
}

static NSDictionary *TestManifest(NSArray<NSData *> *payloads) {
    NSMutableArray<NSDictionary *> *fixtures = [NSMutableArray array];
    NSMutableArray<NSString *> *fixtureIDs = [NSMutableArray array];
    for (NSUInteger index = 0; index < payloads.count; ++index) {
        NSString *fixtureID = [NSString stringWithFormat:@"fixture-%lu", (unsigned long)index];
        NSString *path = [NSString stringWithFormat:@"file-%lu.bin", (unsigned long)index];
        [fixtureIDs addObject:fixtureID];
        [fixtures addObject:@{
            @"fixture_id": fixtureID,
            @"files": @[@{
                @"path": path, @"role": @"payload", @"size": @(payloads[index].length),
                @"sha256": BrokerDigest(payloads[index])
            }]
        }];
    }
    return @{
        @"schema_version": @2,
        @"source_authority": @"service_protected_snapshot_v1",
        @"plan_sha256": [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0],
        @"rules_sha256": [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0],
        @"coverage_mode": @"mandatory_full_plan",
        @"selected_fixture_ids": fixtureIDs,
        @"fixtures": fixtures
    };
}

static NSArray<NSDictionary *> *TestMembers(NSDictionary *manifest) {
    NSMutableArray<NSDictionary *> *members = [NSMutableArray array];
    for (NSDictionary *fixture in manifest[@"fixtures"]) {
        for (NSDictionary *file in fixture[@"files"]) {
            [members addObject:@{
                @"path": [(NSString *)fixture[@"fixture_id"]
                    stringByAppendingFormat:@"/%@", (NSString *)file[@"path"]],
                @"size": (NSNumber *)file[@"size"], @"sha256": (NSString *)file[@"sha256"]
            }];
        }
    }
    return members;
}

static NSData *TestHeaderForManifest(NSDictionary *manifest) {
    NSDictionary *header = @{
        @"schema_version": @1, @"session_id": @"session-1",
        @"manifest_sha256": (NSString *)AQDigest(@"", manifest, NULL),
        @"generation": @2, @"members": TestMembers(manifest)
    };
    return AQCanonicalJSON(header, NULL);
}

static NSData *TestFrameWithHeader(NSData *headerData, NSData *payload,
                                   NSMutableData **transcriptOut);

static NSData *TestFrameWithManifest(NSDictionary *manifest,
                                     NSArray<NSData *> *payloads,
                                     NSMutableData **transcriptOut) {
    NSMutableData *payload = [NSMutableData data];
    for (NSData *entry in payloads) [payload appendData:entry];
    return TestFrameWithHeader(TestHeaderForManifest(manifest), payload, transcriptOut);
}

static NSData *TestFrameWithHeader(NSData *headerData, NSData *member,
                                   NSMutableData **transcriptOut) {
    NSMutableData *transcript = [NSMutableData dataWithBytes:"AQSNAP1\n" length:8];
    uint8_t length[8] = {0};
    uint64_t value = headerData.length;
    for (NSInteger index = 7; index >= 0; --index) { length[index] = value & 0xff; value >>= 8; }
    [transcript appendBytes:length length:8];
    [transcript appendData:headerData];
    [transcript appendData:member];
    NSMutableData *frame = [transcript mutableCopy];
    [frame appendBytes:"AQEND1\r\n" length:8];
    [frame appendData:[NSData dataWithBytes:(uint8_t[32]){0} length:32]];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(transcript.bytes, (CC_LONG)transcript.length, digest);
    [frame replaceBytesInRange:NSMakeRange(frame.length - 32, 32) withBytes:digest length:32];
    if (transcriptOut != NULL) *transcriptOut = transcript;
    return frame;
}

static NSData *TestFrame(NSDictionary *manifest, NSData *member, NSMutableData **transcriptOut) {
    return TestFrameWithManifest(manifest, @[member], transcriptOut);
}

static AQBrokerExportVerifier *TestExportVerifierWithSink(AQBrokerExportSink sink,
                                                                  NSDictionary *manifest,
                                                                  NSString *sessionID,
                                                                  uint64_t generation,
                                                                  NSString *requestID,
                                                                  NSError **error) {
    return [[AQBrokerExportVerifier alloc] initWithSink:sink
                                      expectedSessionID:sessionID
                                     expectedGeneration:generation
                              expectedManifestSHA256:(NSString *)AQDigest(@"", manifest, NULL)
                                    authorizationSHA256:
                                        [@"b" stringByPaddingToLength:64
                                                            withString:@"b"
                                                           startingAtIndex:0]
                                       approvedManifest:manifest
                                              requestID:requestID
                                  deadlineNanoseconds:BrokerTestDeadlineOverride != 0 ?
                                      BrokerTestDeadlineOverride :
                                      AQBrokerSystemClockNanoseconds() + 600ULL * NSEC_PER_SEC
                                               clock:^uint64_t {
                                                   return AQBrokerSystemClockNanoseconds();
                                               }
                                    receiptDirectory:BrokerReceiptDirectory()
                                                  error:error];
}

static void TestExportVerifier(void) {
    NSData *member = [@"synthetic member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    NSMutableData *received = [NSMutableData data];
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
            [received appendData:bytes];
            return YES;
        }, manifest, @"session-1", 2, @"request-1", &error);
    BROKER_CHECK(verifier != nil);
    for (NSUInteger index = 0; index < frame.length; ++index) {
        BROKER_CHECK([verifier consumeData:[frame subdataWithRange:NSMakeRange(index, 1)] error:&error]);
    }
    BROKER_CHECK(received.length == 0);
    BROKER_CHECK([verifier finishWithError:&error]);
    BROKER_CHECK([received isEqualToData:member]);
    NSDictionary *completion = verifier.completion;
    BROKER_CHECK([completion[@"status"] isEqual:@"VERIFIED_RECEIVER_COMPLETION"]);
    BROKER_CHECK([completion[@"code"] isEqual:@"BROKER_RECEIVER_RECEIPT_DURABLE"]);
    BROKER_CHECK([completion[@"request_id"] isEqual:@"request-1"]);
    BROKER_CHECK([completion[@"session_id"] isEqual:@"session-1"]);
    BROKER_CHECK([completion[@"generation"] isEqual:@2]);
    BROKER_CHECK([completion[@"member_count"] isEqual:@1]);
    BROKER_CHECK([completion[@"members"] isEqualToArray:TestMembers(manifest)]);
    BROKER_CHECK([completion[@"durable"] isEqual:@YES]);
    NSString *receiptPath = completion[@"receipt_path"];
    BROKER_CHECK(receiptPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:receiptPath]);
}

static void TestDeliveredChunksRemainOwnedAcrossReuse(void) {
    const NSUInteger chunkLimit = 64 * 1024;
    NSMutableData *member = [NSMutableData dataWithLength:(2 * chunkLimit) + 257];
    uint8_t *memberBytes = member.mutableBytes;
    for (NSUInteger index = 0; index < member.length; ++index) {
        memberBytes[index] = (uint8_t)((index * 37 + 11) & 0xff);
    }
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    NSMutableArray<NSData *> *retainedChunks = [NSMutableArray array];
    __block NSData *firstChunkCopy = nil;
    __block uint64_t nextOffset = 0;
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        ^BOOL(__unused NSString *path, NSData *bytes, uint64_t offset) {
            BROKER_CHECK(bytes.length > 0 && bytes.length <= chunkLimit);
            BROKER_CHECK(offset == nextOffset);
            if (retainedChunks.count == 0) {
                firstChunkCopy = [member subdataWithRange:NSMakeRange(0, bytes.length)];
            } else {
                BROKER_CHECK([retainedChunks.firstObject isEqualToData:firstChunkCopy]);
            }
            [retainedChunks addObject:bytes];
            nextOffset += bytes.length;
            return YES;
        }, manifest, @"session-1", 2, @"request-owned-chunks", &error);
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);
    BROKER_CHECK([verifier finishWithError:&error]);
    BROKER_CHECK(retainedChunks.count == 3);
    NSMutableData *reconstructed = [NSMutableData data];
    NSUInteger memberOffset = 0;
    for (NSData *chunk in retainedChunks) {
        BROKER_CHECK([chunk isEqualToData:[member subdataWithRange:NSMakeRange(memberOffset, chunk.length)]]);
        [reconstructed appendData:chunk];
        memberOffset += chunk.length;
    }
    BROKER_CHECK([reconstructed isEqualToData:member]);
}

static void TestNoCopyStorageReuseCorruptsRetainedData(void) {
    uint8_t reusable[] = {0x11, 0x22, 0x33, 0x44};
    NSData *expected = [NSData dataWithBytes:reusable length:sizeof(reusable)];
    NSData *aliased = [NSData dataWithBytesNoCopy:reusable length:sizeof(reusable) freeWhenDone:NO];
    memset(reusable, 0xee, sizeof(reusable));
    const uint8_t expectedBytes[] = {0x11, 0x22, 0x33, 0x44};
    BROKER_CHECK([expected isEqualToData:[NSData dataWithBytes:expectedBytes length:sizeof(expectedBytes)]]);
    BROKER_CHECK(![aliased isEqualToData:expected]);
}

static void TestSinkFailurePreventsCompletion(void) {
    NSData *member = [@"sink failure" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    __block NSUInteger deliveries = 0;
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        ^BOOL(__unused NSString *path, __unused NSData *bytes, __unused uint64_t offset) {
            deliveries++;
            return NO;
        }, manifest, @"session-1", 2, @"request-sink-failure", &error);
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);
    BROKER_CHECK(![verifier finishWithError:&error]);
    BROKER_CHECK(deliveries == 1);
    BROKER_CHECK(verifier.completion == nil);
    BROKER_CHECK(error.code == AQBrokerSpoolUnavailable);
}

static void TestCompleteWriteHelper(void) {
    NSData *payload = [@"complete write payload" dataUsingEncoding:NSUTF8StringEncoding];
    __block NSUInteger calls = 0;
    __block NSMutableData *written = [NSMutableData data];
    AQBrokerTestWriteOperation partialWriter =
        ^ssize_t(int __unused fd, const void *bytes, size_t length) {
            NSUInteger call = calls++;
            if (call == 0) {
                [written appendBytes:bytes length:1];
                return 1;
            }
            if (call == 1) {
                errno = EINTR;
                return -1;
            }
            NSUInteger count = call == 2 ? MIN((NSUInteger)2, (NSUInteger)length) : (NSUInteger)length;
            [written appendBytes:bytes length:count];
            return (ssize_t)count;
        };
    NSError *error = [NSError errorWithDomain:@"stale" code:1 userInfo:nil];
    BROKER_CHECK(AQBrokerTestWriteAll(STDOUT_FILENO, payload, partialWriter, &error));
    BROKER_CHECK(calls == 4);
    BROKER_CHECK([written isEqualToData:payload]);
    BROKER_CHECK(error == nil);

    calls = 0;
    AQBrokerTestWriteOperation zeroWriter =
        ^ssize_t(int __unused fd, __unused const void *bytes, __unused size_t length) {
            calls++;
            return 0;
        };
    BROKER_CHECK(!AQBrokerTestWriteAll(STDOUT_FILENO, payload, zeroWriter, &error));
    BROKER_CHECK(calls == 1);
    BROKER_CHECK(error.code == EIO);
    BROKER_CHECK(!AQBrokerTestWriteAll(STDOUT_FILENO, payload, zeroWriter, NULL));

    calls = 0;
    AQBrokerTestWriteOperation failingWriter =
        ^ssize_t(int __unused fd, __unused const void *bytes, __unused size_t length) {
            calls++;
            errno = EPIPE;
            return -1;
        };
    BROKER_CHECK(!AQBrokerTestWriteAll(STDOUT_FILENO, payload, failingWriter, &error));
    BROKER_CHECK(calls == 1);
    BROKER_CHECK(error.code == EPIPE);

    AQBrokerTestWriteOperation overrunWriter =
        ^ssize_t(int __unused fd, __unused const void *bytes, size_t length) {
            return (ssize_t)length + 1;
        };
    BROKER_CHECK(!AQBrokerTestWriteAll(STDOUT_FILENO, payload, overrunWriter, &error));
    BROKER_CHECK(error.code == EPROTO);

    calls = 0;
    AQBrokerTestWriteOperation emptyWriter =
        ^ssize_t(int __unused fd, __unused const void *bytes, __unused size_t length) {
            calls++;
            return 0;
        };
    BROKER_CHECK(AQBrokerTestWriteAll(STDOUT_FILENO, [NSData data], emptyWriter, &error));
    BROKER_CHECK(calls == 0);
    BROKER_CHECK(!AQBrokerTestWriteAll(STDOUT_FILENO, payload, nil, &error));
    BROKER_CHECK(error.code == EINVAL);
}

static void TestCanonicalHeaderRequired(void) {
    NSData *member = [@"member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSMutableData *noncanonical = [TestHeaderForManifest(manifest) mutableCopy];
    [noncanonical appendBytes:" " length:1];
    NSData *frame = TestFrameWithHeader(noncanonical, member, NULL);
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        nil, manifest, @"session-1", 2, @"request-1", NULL);
    NSError *error = nil;
    BROKER_CHECK(![verifier consumeData:frame error:&error]);
    BROKER_CHECK(error.code == AQBrokerInvalidFrame);
}

static void TestNilSinkRejectedAfterValidFrame(void) {
    NSData *member = [@"member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        nil, manifest, @"session-1", 2, @"request-nil-sink", &error);
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);
    BROKER_CHECK(verifier.completion == nil);
    BROKER_CHECK(![verifier finishWithError:&error]);
    BROKER_CHECK(error != nil && error.code == AQBrokerSpoolUnavailable);
    BROKER_CHECK(verifier.completion == nil);
}

static void TestExportDeliveryWaitsForVerification(void) {
    NSData *first = [@"first member" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *second = [@"second member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[first, second]);
    NSData *frame = TestFrameWithManifest(manifest, @[first, second], NULL);
    NSMutableData *received = [NSMutableData data];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        ^(NSString *path, NSData *bytes, __unused uint64_t offset) {
            [paths addObject:path];
            [received appendData:bytes];
            return YES;
        }, manifest, @"session-1", 2, @"request-2", &error);
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);
    BROKER_CHECK(verifier.completion == nil);
    BROKER_CHECK(received.length == 0);
    BROKER_CHECK([verifier finishWithError:&error]);
    NSMutableData *expected = [first mutableCopy];
    [expected appendData:second];
    BROKER_CHECK([received isEqualToData:expected]);
    NSArray *expectedPaths = @[@"fixture-0/file-0.bin", @"fixture-1/file-1.bin"];
    BROKER_CHECK([paths isEqualToArray:expectedPaths]);
    BROKER_CHECK([verifier.completion[@"request_id"] isEqual:@"request-2"]);
    BROKER_CHECK([verifier.completion[@"member_count"] isEqual:@2]);
}

static void TestExportVerificationFailuresNeverDeliverBytes(void) {
    NSData *member = [@"member bytes" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    NSUInteger headerLength = ((NSData *)TestHeaderForManifest(manifest)).length;
    NSUInteger memberStart = 8 + 8 + headerLength;

    NSMutableData *memberFailure = [frame mutableCopy];
    ((uint8_t *)memberFailure.mutableBytes)[memberStart] ^= 1;
    __block NSUInteger memberFailureBytes = 0;
    NSError *error = nil;
    AQBrokerExportVerifier *memberVerifier = TestExportVerifierWithSink(
        ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
            memberFailureBytes += bytes.length;
            return YES;
        }, manifest, @"session-1", 2, @"request-member", &error);
    BROKER_CHECK(![memberVerifier consumeData:memberFailure error:&error]);
    BROKER_CHECK(error.code == AQBrokerFrameMemberMismatch);
    BROKER_CHECK(memberFailureBytes == 0);
    BROKER_CHECK(memberVerifier.completion == nil);

    NSMutableData *terminalFailure = [frame mutableCopy];
    ((uint8_t *)terminalFailure.mutableBytes)[frame.length - 1] ^= 1;
    __block NSUInteger terminalFailureBytes = 0;
    AQBrokerExportVerifier *terminalVerifier = TestExportVerifierWithSink(
        ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
            terminalFailureBytes += bytes.length;
            return YES;
        }, manifest, @"session-1", 2, @"request-terminal", &error);
    BROKER_CHECK(![terminalVerifier consumeData:terminalFailure error:&error]);
    BROKER_CHECK(error.code == AQBrokerFrameDigestMismatch);
    BROKER_CHECK(terminalFailureBytes == 0);
    BROKER_CHECK(terminalVerifier.completion == nil);
}

static void TestWrongExportBindingRejected(void) {
    NSData *member = [@"bound member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    __block NSUInteger deliveredBytes = 0;
    AQBrokerExportSink sink = ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
        deliveredBytes += bytes.length;
        return YES;
    };
    NSError *error = nil;

    AQBrokerExportVerifier *wrongSession = TestExportVerifierWithSink(
        sink, manifest, @"session-2", 2, @"request-wrong-session", &error);
    BROKER_CHECK(![wrongSession consumeData:frame error:&error]);
    BROKER_CHECK(error.code == AQBrokerBindingMismatch);

    AQBrokerExportVerifier *wrongGeneration = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 3, @"request-wrong-generation", &error);
    BROKER_CHECK(![wrongGeneration consumeData:frame error:&error]);
    BROKER_CHECK(error.code == AQBrokerBindingMismatch);

    NSData *otherMember = [@"another member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *wrongManifest = TestManifest(@[otherMember]);
    AQBrokerExportVerifier *manifestMismatch = TestExportVerifierWithSink(
        sink, wrongManifest, @"session-1", 2, @"request-wrong-manifest", &error);
    BROKER_CHECK(![manifestMismatch consumeData:frame error:&error]);
    BROKER_CHECK(error.code == AQBrokerBindingMismatch);

    NSDictionary *header = AQParseJSON(TestHeaderForManifest(manifest), NULL);
    NSMutableDictionary *alteredHeader = [header mutableCopy];
    NSMutableArray *alteredMembers = [header[@"members"] mutableCopy];
    NSMutableDictionary *alteredMember = [alteredMembers[0] mutableCopy];
    alteredMember[@"path"] = @"fixture-0/other.bin";
    alteredMembers[0] = alteredMember;
    alteredHeader[@"members"] = alteredMembers;
    NSData *alteredHeaderData = AQCanonicalJSON(alteredHeader, NULL);
    NSData *alteredFrame = TestFrameWithHeader(alteredHeaderData, member, NULL);
    AQBrokerExportVerifier *memberMismatch = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-wrong-member", &error);
    BROKER_CHECK(![memberMismatch consumeData:alteredFrame error:&error]);
    BROKER_CHECK(error.code == AQBrokerBindingMismatch);
    BROKER_CHECK(deliveredBytes == 0);
}

static void TestTrailingBytesRejectedWithoutDelivery(void) {
    NSData *member = [@"trailing member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSMutableData *frame = [TestFrame(manifest, member, NULL) mutableCopy];
    [frame appendBytes:"x" length:1];
    __block NSUInteger deliveredBytes = 0;
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
            deliveredBytes += bytes.length;
            return YES;
        }, manifest, @"session-1", 2, @"request-trailing", &error);
    BROKER_CHECK(![verifier consumeData:frame error:&error]);
    BROKER_CHECK(error.code == AQBrokerInvalidFrame);
    BROKER_CHECK(deliveredBytes == 0);
    BROKER_CHECK(verifier.completion == nil);
}

static void TestSpoolMetadataRejectsMutation(void) {
    NSData *member = [@"metadata member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    __block NSUInteger deliveredBytes = 0;
    AQBrokerExportSink sink = ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
        deliveredBytes += bytes.length;
        return YES;
    };
    NSError *error = nil;

    AQBrokerExportVerifier *metadataVerifier = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-spool-metadata", &error);
    BROKER_CHECK(metadataVerifier != nil);
    BROKER_CHECK([metadataVerifier consumeData:frame error:&error]);
    int descriptor = AQBrokerTestSpoolDescriptor(metadataVerifier);
    NSString *formerPath = AQBrokerTestSpoolPath(metadataVerifier);
    BROKER_CHECK(descriptor >= 0 && formerPath != nil);
    if (descriptor < 0 || formerPath == nil) return;
    struct stat info = {0};
    BROKER_CHECK(fstat(descriptor, &info) == 0);
    BROKER_CHECK(S_ISREG(info.st_mode));
    BROKER_CHECK((info.st_mode & 0777) == 0600);
    BROKER_CHECK(info.st_nlink == 0);
    int descriptorFlags = fcntl(descriptor, F_GETFD);
    BROKER_CHECK(descriptorFlags >= 0 && (descriptorFlags & FD_CLOEXEC) != 0);

    errno = 0;
    BROKER_CHECK(lstat(formerPath.fileSystemRepresentation, &info) == -1);
    BROKER_CHECK(errno == ENOENT);

    BROKER_CHECK(fchmod(descriptor, 0644) == 0);
    error = nil;
    BROKER_CHECK(![metadataVerifier finishWithError:&error]);
    BROKER_CHECK(error.code == AQBrokerSpoolUnavailable);
    BROKER_CHECK(metadataVerifier.completion == nil);

    AQBrokerExportVerifier *flagsVerifier = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-spool-flags", &error);
    BROKER_CHECK(flagsVerifier != nil);
    BROKER_CHECK([flagsVerifier consumeData:frame error:&error]);
    int flagsDescriptor = AQBrokerTestSpoolDescriptor(flagsVerifier);
    int flags = fcntl(flagsDescriptor, F_GETFD);
    BROKER_CHECK(flags >= 0 && (flags & FD_CLOEXEC) != 0);
    BROKER_CHECK(fcntl(flagsDescriptor, F_SETFD, flags & ~FD_CLOEXEC) == 0);
    error = nil;
    BROKER_CHECK(![flagsVerifier finishWithError:&error]);
    BROKER_CHECK(error.code == AQBrokerSpoolUnavailable);
    BROKER_CHECK(flagsVerifier.completion == nil);
    BROKER_CHECK(deliveredBytes == 0);
}

static void TestSpoolIsolationUnavailableFailsBeforeDelivery(void) {
    NSData *member = [@"isolation member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    __block NSUInteger deliveredBytes = 0;
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
            deliveredBytes += bytes.length;
            return YES;
        }, manifest, @"session-1", 2, @"request-spool-isolation-unavailable", &error);
    BROKER_CHECK(verifier != nil);
    if (verifier == nil) return;

    AQBrokerTestForceSpoolUnavailableForTesting(YES);
    BOOL accepted = [verifier consumeData:frame error:&error];
    AQBrokerTestForceSpoolUnavailableForTesting(NO);
    BROKER_CHECK(!accepted);
    BROKER_CHECK(error.code == AQBrokerSpoolUnavailable);
    BROKER_CHECK(deliveredBytes == 0);
    BROKER_CHECK(verifier.completion == nil);
    BROKER_CHECK(AQBrokerTestSpoolDescriptor(verifier) == -1);
    BROKER_CHECK(AQBrokerTestSpoolPath(verifier) == nil);
}

/** Replaces the former spool pathname, mutates the replacement, and verifies
 * that successful delivery still reads the original anonymous descriptor and
 * that closing that descriptor leaves the replacement in place. */
static void TestSpoolMutationBeforeDeliveryCannotProduceReceipt(void) {
    NSData *member = [@"spool member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    __block NSUInteger deliveredBytes = 0;
    AQBrokerExportSink sink = ^(__unused NSString *path, NSData *bytes,
                                __unused uint64_t offset) {
        deliveredBytes += bytes.length;
        return YES;
    };
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-spool-mutation", &error);
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);

    NSRange memberRange = [frame rangeOfData:member
                                    options:0
                                      range:NSMakeRange(0, frame.length)];
    BROKER_CHECK(memberRange.location != NSNotFound);
    int descriptor = AQBrokerTestSpoolDescriptor(verifier);
    uint8_t corruptedByte = ((const uint8_t *)member.bytes)[0] ^ 0xff;
    BROKER_CHECK(pwrite(descriptor, &corruptedByte, 1,
                        (off_t)memberRange.location) == 1);

    error = nil;
    BROKER_CHECK(![verifier finishWithError:&error]);
    BROKER_CHECK(deliveredBytes == 0);
    BROKER_CHECK(verifier.completion == nil);
}

static void TestSpoolMutationDuringDeliveryCannotProduceReceipt(void) {
    NSData *member = [NSMutableData dataWithLength:128 * 1024];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    NSRange memberRange = [frame rangeOfData:member
                                    options:0
                                      range:NSMakeRange(0, frame.length)];
    BROKER_CHECK(memberRange.location != NSNotFound);
    __block int descriptor = -1;
    __block BOOL mutated = NO;
    __block NSUInteger deliveredBytes = 0;
    AQBrokerExportSink sink = ^(__unused NSString *path, NSData *bytes,
                                __unused uint64_t offset) {
        if (!mutated) {
            uint8_t corruptedByte = 0xff;
            off_t nextChunk = (off_t)(memberRange.location + bytes.length);
            if (pwrite(descriptor, &corruptedByte, 1, nextChunk) != 1) return NO;
            mutated = YES;
        }
        deliveredBytes += bytes.length;
        return YES;
    };
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-spool-interleaving", &error);
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);
    descriptor = AQBrokerTestSpoolDescriptor(verifier);
    error = nil;
    BROKER_CHECK(![verifier finishWithError:&error]);
    BROKER_CHECK(mutated);
    BROKER_CHECK(deliveredBytes > 0);
    BROKER_CHECK(verifier.completion == nil);
}

static void TestSpoolPathReplacementCannotAffectVerifiedBytes(void) {
    NSData *member = [@"verified descriptor member" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *foreignBytes = [@"foreign replacement" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *mutatedBytes = [@"mutated replacement" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    NSMutableData *received = [NSMutableData data];
    __block NSUInteger deliveries = 0;
    AQBrokerExportSink sink = ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
        [received appendData:bytes];
        deliveries++;
        return YES;
    };
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-spool-path-replacement", &error);
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);
    int descriptor = AQBrokerTestSpoolDescriptor(verifier);
    NSString *formerPath = AQBrokerTestSpoolPath(verifier);
    BROKER_CHECK(descriptor >= 0 && formerPath != nil);
    if (descriptor < 0 || formerPath == nil) return;

    BOOL created = BrokerCreateForeignFile(formerPath, foreignBytes);
    BROKER_CHECK(created);
    if (!created) return;
    struct stat spoolInfo = {0};
    struct stat foreignInfo = {0};
    BROKER_CHECK(fstat(descriptor, &spoolInfo) == 0);
    BROKER_CHECK(lstat(formerPath.fileSystemRepresentation, &foreignInfo) == 0);
    BROKER_CHECK(spoolInfo.st_dev != foreignInfo.st_dev || spoolInfo.st_ino != foreignInfo.st_ino);
    BROKER_CHECK(spoolInfo.st_nlink == 0);

    int foreignDescriptor = open(formerPath.fileSystemRepresentation,
                                 O_WRONLY | O_TRUNC | O_CLOEXEC);
    BROKER_CHECK(foreignDescriptor >= 0);
    if (foreignDescriptor >= 0) {
        BROKER_CHECK(AQBrokerWriteAll(foreignDescriptor, mutatedBytes, NULL));
        BROKER_CHECK(close(foreignDescriptor) == 0);
    }
    BROKER_CHECK([BrokerReadFile(formerPath) isEqualToData:mutatedBytes]);

    BROKER_CHECK([verifier finishWithError:&error]);
    BROKER_CHECK(deliveries > 0);
    BROKER_CHECK([received isEqualToData:member]);
    BROKER_CHECK(AQBrokerTestSpoolDescriptor(verifier) == -1);
    BROKER_CHECK([BrokerReadFile(formerPath) isEqualToData:mutatedBytes]);
    BROKER_CHECK(unlink(formerPath.fileSystemRepresentation) == 0);
}

/** Forces metadata rejection after a foreign file replaces the former spool
 * pathname, then verifies discard cleanup closes only the anonymous descriptor
 * and cannot unlink the replacement file. */
static void TestSpoolDiscardRetainsForeignReplacement(void) {
    NSData *member = [@"discard descriptor member" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *foreignBytes = [@"foreign replacement survives discard" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    __block NSUInteger deliveries = 0;
    AQBrokerExportSink sink = ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
        deliveries += bytes.length;
        return YES;
    };
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-spool-discard-replacement", &error);
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);
    int descriptor = AQBrokerTestSpoolDescriptor(verifier);
    NSString *formerPath = AQBrokerTestSpoolPath(verifier);
    BROKER_CHECK(descriptor >= 0 && formerPath != nil);
    if (descriptor < 0 || formerPath == nil) return;

    BOOL created = BrokerCreateForeignFile(formerPath, foreignBytes);
    BROKER_CHECK(created);
    if (!created) return;
    BROKER_CHECK(fchmod(descriptor, 0644) == 0);
    error = nil;
    BROKER_CHECK(![verifier finishWithError:&error]);
    BROKER_CHECK(error.code == AQBrokerSpoolUnavailable);
    BROKER_CHECK(verifier.completion == nil);
    BROKER_CHECK(deliveries == 0);
    BROKER_CHECK(AQBrokerTestSpoolDescriptor(verifier) == -1);
    BROKER_CHECK([BrokerReadFile(formerPath) isEqualToData:foreignBytes]);
    BROKER_CHECK(unlink(formerPath.fileSystemRepresentation) == 0);
}

static void TestSpoolCapacityReserveBoundary(void) {
    NSData *member = [@"capacity member" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    NSUInteger headerPrefixLength = 16 + TestHeaderForManifest(manifest).length;
    NSData *headerPrefix = [frame subdataWithRange:NSMakeRange(0, headerPrefixLength)];
    NSData *remainingFrame = [frame subdataWithRange:NSMakeRange(
        headerPrefixLength, frame.length - headerPrefixLength)];
    const uint64_t reserveBytes = 2ULL * 1024 * 1024 * 1024;
    __block NSUInteger deliveredBytes = 0;
    AQBrokerExportSink sink = ^(__unused NSString *path, NSData *bytes, __unused uint64_t offset) {
        deliveredBytes += bytes.length;
        return YES;
    };
    NSError *error = nil;

    AQBrokerTestSetSpoolAvailableBytes((uint64_t)remainingFrame.length + reserveBytes);
    AQBrokerExportVerifier *admitted = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-capacity-admitted", &error);
    BROKER_CHECK(admitted != nil);
    BROKER_CHECK([admitted consumeData:headerPrefix error:&error]);
    AQBrokerTestClearSpoolAvailableBytes();
    BROKER_CHECK([admitted consumeData:remainingFrame error:&error]);
    BROKER_CHECK([admitted finishWithError:&error]);
    BROKER_CHECK([admitted.completion[@"status"] isEqual:@"VERIFIED_RECEIVER_COMPLETION"]);
    BROKER_CHECK(deliveredBytes == member.length);

    deliveredBytes = 0;
    AQBrokerTestSetSpoolAvailableBytes((uint64_t)remainingFrame.length + reserveBytes - 1);
    AQBrokerExportVerifier *denied = TestExportVerifierWithSink(
        sink, manifest, @"session-1", 2, @"request-capacity-denied", &error);
    BROKER_CHECK(denied != nil);
    BROKER_CHECK(![denied consumeData:headerPrefix error:&error]);
    AQBrokerTestClearSpoolAvailableBytes();
    BROKER_CHECK(error.code == AQBrokerSpoolCapacityDenied);
    BROKER_CHECK(denied.completion == nil);
    BROKER_CHECK(deliveredBytes == 0);
}

static NSDictionary *BrokerHelloRequest(NSString *requestID, uint64_t sequence,
                                        uint64_t deadline) {
    return @{
        @"schema_version": @1,
        @"operation": @"hello",
        @"request_id": requestID,
        @"nonce": [NSString stringWithFormat:@"nonce-%@", requestID],
        @"grant_id": @"grant-1",
        @"sequence": @(sequence),
        @"service_boot_id": @"boot-1",
        @"installation_id": @"installation-1",
        @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
        @"deadline_ns": @(deadline)
    };
}

static NSDictionary *BrokerHelloResponse(NSString *requestID, NSString *sessionID,
                                         NSString *connectionID) {
    return @{
        @"status": @"OK",
        @"request_id": requestID,
        @"result": @{@"session_id": sessionID, @"connection_id": connectionID}
    };
}

static NSDictionary *BrokerSignedRequest(NSString *operation, NSString *requestID,
                                         uint64_t sequence, uint64_t deadline,
                                         NSString *sessionID, NSString *connectionID,
                                         NSString *ownerKeyID) {
    NSDictionary *freshness = @{
        @"schema_version": @1,
        @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1",
        @"broker_revision": @"broker-1",
        @"owner_key_id": ownerKeyID,
        @"connection_id": connectionID,
        @"session_id": sessionID,
        @"request_id": requestID,
        @"sequence": @(sequence),
        @"operation": operation,
        @"request_sha256": [@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0],
        @"authorization_sha256": [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0],
        @"deadline_ns": @(deadline)
    };
    NSData *encoded = AQCanonicalJSON(freshness, NULL);
    return @{
        @"schema_version": @1,
        @"operation": operation,
        @"request_id": requestID,
        @"connection_id": connectionID,
        @"session_id": sessionID,
        @"freshness_envelope": [encoded base64EncodedStringWithOptions:0],
        @"freshness_signature": @"c2lnbmF0dXJl"
    };
}

static NSDictionary *BrokerOKResponse(NSString *requestID) {
    return @{@"status": @"OK", @"request_id": requestID, @"result": @{@"accepted": @YES}};
}

static void TestSequentialSessionOrdering(void) {
    __block uint64_t now = 100;
AQBrokerSequentialSession *freshSession = [[AQBrokerSequentialSession alloc]
initWithClock:^uint64_t { return now; }];
NSError *freshError = nil;
uint64_t freshToken = 0;
NSDictionary *exportBeforeHello = BrokerSignedRequest(
    @"export", @"export-before-hello", 1, 1000,
    @"session-1", @"connection-1", @"owner-key-1");
BROKER_CHECK(![freshSession beginRequest:exportBeforeHello
                                  token:&freshToken
                                  error:&freshError]);
BROKER_CHECK(freshError != nil);
BROKER_CHECK(freshToken == 0);
BROKER_CHECK(!freshSession.hasActiveRequest);
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return now; }];
    NSError *error = nil;
    uint64_t helloToken = 0;
    NSDictionary *hello = BrokerHelloRequest(@"hello-1", 1, 1000);
    BROKER_CHECK([session beginRequest:hello token:&helloToken error:&error]);
    BROKER_CHECK(helloToken == 1);
    BROKER_CHECK(session.hasActiveRequest);

    uint64_t rejectedToken = 0;
    BOOL state = [session beginRequest:hello token:&rejectedToken error:&error];
    BROKER_CHECK(!state);
    BROKER_CHECK(error.code == AQBrokerOperationInProgress);
    BROKER_CHECK(rejectedToken == 0);

    BROKER_CHECK([session acceptResponseForToken:helloToken
        response:BrokerHelloResponse(@"hello-1", @"session-1", @"connection-1") error:&error]);
    BROKER_CHECK([session completeRequestForToken:helloToken outcomeKnown:YES error:&error]);
    BROKER_CHECK([session.sessionID isEqual:@"session-1"]);
    BROKER_CHECK([session.connectionID isEqual:@"connection-1"]);

    NSDictionary *skipped = BrokerSignedRequest(@"stage", @"stage-2", 2, 1000,
        @"session-1", @"connection-1", @"owner-key-1");
    BROKER_CHECK(![session beginRequest:skipped token:&rejectedToken error:&error]);
    BROKER_CHECK(error.code == AQBrokerSequenceMismatch);

    NSDictionary *first = BrokerSignedRequest(@"stage", @"stage-1", 1, 1000,
        @"session-1", @"connection-1", @"owner-key-1");
    uint64_t firstToken = 0;
    BROKER_CHECK([session beginRequest:first token:&firstToken error:&error]);
    BROKER_CHECK([session acceptResponseForToken:firstToken
        response:BrokerOKResponse(@"stage-1") error:&error]);
    BROKER_CHECK([session completeRequestForToken:firstToken outcomeKnown:YES error:&error]);

    BROKER_CHECK(![session beginRequest:first token:&rejectedToken error:&error]);
    BROKER_CHECK(error.code == AQBrokerSequenceMismatch);

    NSDictionary *wrongOwner = BrokerSignedRequest(@"inspect", @"inspect-wrong-owner", 2, 1000,
        @"session-1", @"connection-1", @"different-owner-key");
    BROKER_CHECK(![session beginRequest:wrongOwner token:&rejectedToken error:&error]);
    BROKER_CHECK(error.code == AQBrokerSessionOwnershipMismatch);
}

static void TestReconnectBlocksMutationAndAllowsInspection(void) {
    __block uint64_t now = 100;
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return now; }];
    NSError *error = nil;
    uint64_t token = 0;
    BROKER_CHECK([session beginRequest:BrokerHelloRequest(@"hello-1", 1, 1000)
        token:&token error:&error]);
    BROKER_CHECK([session acceptResponseForToken:token
        response:BrokerHelloResponse(@"hello-1", @"session-1", @"connection-1")
        error:&error]);
    BROKER_CHECK([session completeRequestForToken:token outcomeKnown:YES error:&error]);

    NSDictionary *stage = BrokerSignedRequest(@"stage", @"stage-1", 1, 1000,
        @"session-1", @"connection-1", @"owner-key-1");
    BROKER_CHECK([session beginRequest:stage token:&token error:&error]);
    BROKER_CHECK([session completeRequestForToken:token outcomeKnown:NO error:&error]);
    BROKER_CHECK(session.outcomeUnknown);
    BROKER_CHECK(session.requiresFreshAuthentication);
    BROKER_CHECK(session.reconnectGuard.uncertainEffect);

    BROKER_CHECK([session connectionOpened]);
    BROKER_CHECK([session beginRequest:BrokerHelloRequest(@"hello-2", 2, 1000)
        token:&token error:&error]);
    BROKER_CHECK([session acceptResponseForToken:token
        response:BrokerHelloResponse(@"hello-2", @"session-2", @"connection-2")
        error:&error]);
    BROKER_CHECK([session completeRequestForToken:token outcomeKnown:YES error:&error]);
    BROKER_CHECK(!session.requiresFreshAuthentication);
    BROKER_CHECK([session.sessionID isEqual:@"session-2"]);

    NSDictionary *replay = BrokerSignedRequest(@"stage", @"stage-replay", 1, 1000,
        @"session-2", @"connection-2", @"owner-key-1");
    BROKER_CHECK(![session beginRequest:replay token:&token error:&error]);
    BROKER_CHECK(error.code == AQBrokerUncertainEffect);

    NSDictionary *inspect = BrokerSignedRequest(@"inspect", @"inspect-1", 1, 1000,
        @"session-2", @"connection-2", @"owner-key-1");
    BROKER_CHECK([session beginRequest:inspect token:&token error:&error]);
    BROKER_CHECK([session acceptResponseForToken:token
        response:BrokerOKResponse(@"inspect-1") error:&error]);
    BROKER_CHECK([session completeRequestForToken:token outcomeKnown:YES error:&error]);
}

static void TestDeadlineAndLateReply(void) {
    __block uint64_t now = 100;
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return now; } enforceOrdering:NO];
    NSError *error = nil;
    uint64_t token = 0;
    uint64_t remaining = 0;
    BROKER_CHECK(AQBrokerDeadlineRemaining(125, now, &remaining, &error));
    BROKER_CHECK(remaining == 25);
    BROKER_CHECK(!AQBrokerDeadlineRemaining(100, now, &remaining, &error));
    BROKER_CHECK(error.code == AQBrokerDeadlineExpired);

    AQBrokerSequentialSession *expiredBeforeDispatch = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return now; } enforceOrdering:NO];
    NSDictionary *alreadyExpired = BrokerSignedRequest(@"stage", @"stage-already-expired",
        1, 100, @"session-1", @"connection-1", @"owner-key-1");
    BROKER_CHECK(![expiredBeforeDispatch beginRequest:alreadyExpired
        token:&token error:&error]);
    BROKER_CHECK(error.code == AQBrokerDeadlineExpired);
    BROKER_CHECK(!expiredBeforeDispatch.hasActiveRequest);
    BROKER_CHECK(token == 0);

    NSDictionary *request = BrokerSignedRequest(@"stage", @"stage-timeout", 1, 200,
        @"session-1", @"connection-1", @"owner-key-1");
    BROKER_CHECK([session beginRequest:request token:&token error:&error]);
    BROKER_CHECK([session completeRequestForToken:token outcomeKnown:NO error:&error]);
    BROKER_CHECK(![session acceptResponseForToken:token
        response:BrokerOKResponse(@"stage-timeout") error:&error]);
    BROKER_CHECK(error.code == AQBrokerLateReply);

    AQBrokerSequentialSession *deadlineSession = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return now; } enforceOrdering:NO];
    NSDictionary *expiring = BrokerSignedRequest(@"stage", @"stage-expiring", 2, 110,
        @"session-1", @"connection-1", @"owner-key-1");
    BROKER_CHECK([deadlineSession beginRequest:expiring token:&token error:&error]);
    BROKER_CHECK([deadlineSession remainingNanosecondsForToken:token remaining:&remaining error:&error]);
    BROKER_CHECK(remaining == 10);
    BROKER_CHECK([deadlineSession pollTimeoutMillisecondsForToken:token error:&error] == 1);
    BROKER_CHECK([deadlineSession acceptResponseForToken:token
        response:BrokerOKResponse(@"stage-expiring") error:&error]);
    now = 110;
    BROKER_CHECK(![deadlineSession completeRequestForToken:token outcomeKnown:YES error:&error]);
    BROKER_CHECK(error.code == AQBrokerDeadlineExpired);
    BROKER_CHECK(deadlineSession.outcomeUnknown);
    now = 109;
    BROKER_CHECK(![deadlineSession acceptResponseForToken:token
        response:BrokerOKResponse(@"stage-expiring") error:&error]);
    BROKER_CHECK(error.code == AQBrokerLateReply);
}

static void TestReconnectGuard(void) {
    AQBrokerReconnectGuard *guard = [[AQBrokerReconnectGuard alloc] init];
    BROKER_CHECK([guard dispatchMutation]);
    [guard connectionLostWithOutcomeKnown:NO];
    BROKER_CHECK(guard.uncertainEffect);
    BROKER_CHECK(![guard dispatchMutation]);
    BROKER_CHECK(guard.generation == 2);

    AQBrokerReconnectGuard *known = [[AQBrokerReconnectGuard alloc] init];
    BROKER_CHECK([known connectionOpened]);
    BROKER_CHECK([known dispatchMutation]);
    [known operationCompleted];
    [known connectionLostWithOutcomeKnown:YES];
    BROKER_CHECK(!known.uncertainEffect);
    BROKER_CHECK(known.generation == 2);
    BROKER_CHECK([known connectionOpened]);
    BROKER_CHECK([known canDispatchMutation]);
}

static void TestXPCEnvelopeRelaysExactAuthorization(void) {
    NSData *request = [@"{\"operation\":\"hello\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *authorization = [@"{\"authorization_id\":\"reviewed\"}"
        dataUsingEncoding:NSUTF8StringEncoding];
    int descriptors[2] = {-1, -1};
    BROKER_CHECK(pipe(descriptors) == 0);
    NSDictionary *documents = @{
        @"consent": [@"consent-envelope" dataUsingEncoding:NSUTF8StringEncoding]
            ?: [NSData data],
        @"signature": [@"owner-signature" dataUsingEncoding:NSUTF8StringEncoding]
            ?: [NSData data],
        @"oracles": @[
            [@"oracle" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]
        ]
    };
    xpc_object_t message = AQBrokerCreateXPCRequestMessage(
        request, @[@(descriptors[0])], documents, authorization);
    BROKER_CHECK(message != NULL && xpc_get_type(message) == XPC_TYPE_DICTIONARY);
    size_t requestLength = 0, authorizationLength = 0;
    const void *requestBytes = xpc_dictionary_get_data(message, "request", &requestLength);
    const void *authorizationBytes = xpc_dictionary_get_data(
        message, "authorization", &authorizationLength);
    BROKER_CHECK(requestLength == request.length &&
        memcmp(requestBytes, request.bytes, request.length) == 0);
    BROKER_CHECK(authorizationLength == authorization.length &&
        memcmp(authorizationBytes, authorization.bytes, authorization.length) == 0);
    xpc_object_t xpcDocuments = xpc_dictionary_get_value(message, "documents");
    BROKER_CHECK(xpcDocuments != NULL);
    xpc_object_t consent = xpc_dictionary_get_value(xpcDocuments, "consent");
    xpc_object_t oracles = xpc_dictionary_get_value(xpcDocuments, "oracles");
    BROKER_CHECK(consent != NULL && xpc_get_type(consent) == XPC_TYPE_DATA);
    size_t consentLength = 0;
    const void *consentBytes = xpc_data_get_bytes_ptr(consent);
    consentLength = xpc_data_get_length(consent);
    BROKER_CHECK(consentBytes != NULL &&
        consentLength == [documents[@"consent"] length]);
    BROKER_CHECK(xpc_get_type(oracles) == XPC_TYPE_ARRAY &&
        xpc_array_get_count(oracles) == 1);
    xpc_object_t fds = xpc_dictionary_get_value(message, "source_fds");
    BROKER_CHECK(fds != NULL && xpc_array_get_count(fds) == 1);
    close(descriptors[0]);
    close(descriptors[1]);
}

@interface BrokerNullBytesData : NSData
@end

@implementation BrokerNullBytesData
- (NSUInteger)length { return 1; }
- (const void *)bytes { return NULL; }
@end

static void TestXPCEnvelopeRejectsAuthorizationWithoutBytes(void) {
    NSData *request = [@"{\"operation\":\"hello\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *authorization = [[BrokerNullBytesData alloc] init];
    xpc_object_t message = AQBrokerCreateXPCRequestMessage(request, @[], nil, authorization);
    BROKER_CHECK(message == NULL);
}

static void TestReconnectPreservesImmutableDeadline(void) {
    __block uint64_t now = 100;
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return now; }];
    NSError *error = nil;
    uint64_t token = 0;
    BROKER_CHECK([session beginRequest:BrokerHelloRequest(@"hello-deadline", 1, 1000)
                                 token:&token error:&error]);
    BROKER_CHECK([session acceptResponseForToken:token
        response:BrokerHelloResponse(@"hello-deadline", @"session-deadline", @"connection-1")
        error:&error]);
    BROKER_CHECK([session completeRequestForToken:token outcomeKnown:YES error:&error]);
    [session connectionLostWithOutcomeKnown:YES];
    BROKER_CHECK([session connectionOpened]);
    BROKER_CHECK(![session beginRequest:BrokerHelloRequest(@"hello-rebased", 2, 2000)
                                  token:&token error:&error]);
    BROKER_CHECK(error.code == AQBrokerBindingMismatch);
    BROKER_CHECK([session beginRequest:BrokerHelloRequest(@"hello-preserved", 2, 1000)
                                 token:&token error:&error]);
    BROKER_CHECK([session acceptResponseForToken:token
        response:BrokerHelloResponse(@"hello-preserved", @"session-deadline", @"connection-1")
        error:&error]);
    BROKER_CHECK([session completeRequestForToken:token outcomeKnown:YES error:&error]);
    NSDictionary *shortened = BrokerSignedRequest(@"stage", @"stage-shortened", 1, 999,
        @"session-deadline", @"connection-1", @"owner-key-1");
    BROKER_CHECK(![session beginRequest:shortened token:&token error:&error]);
    BROKER_CHECK(error.code == AQBrokerBindingMismatch);
}

static void TestDeadlineBoundedWrite(void) {
    int descriptors[2] = {-1, -1};
    BROKER_CHECK(pipe(descriptors) == 0);
    int flags = fcntl(descriptors[1], F_GETFL);
    BROKER_CHECK(flags >= 0 && fcntl(descriptors[1], F_SETFL, flags | O_NONBLOCK) == 0);
    uint8_t fill[4096] = {0};
    while (write(descriptors[1], fill, sizeof(fill)) > 0) {}
    NSData *payload = [NSMutableData dataWithLength:1024 * 1024];
    uint64_t deadline = AQBrokerSystemClockNanoseconds() + 50 * NSEC_PER_MSEC;
    NSError *error = nil;
    BROKER_CHECK(!AQBrokerWriteAllUntilDeadline(
        descriptors[1], payload, deadline,
        ^uint64_t { return AQBrokerSystemClockNanoseconds(); }, &error));
    BROKER_CHECK(error.code == AQBrokerDeadlineExpired);
    close(descriptors[0]);
    close(descriptors[1]);
}

static void TestDeadlineIsRecheckedImmediatelyBeforeWrite(void) {
    int descriptors[2] = {-1, -1};
    BROKER_CHECK(pipe(descriptors) == 0);
    int readFlags = fcntl(descriptors[0], F_GETFL);
    BROKER_CHECK(readFlags >= 0 &&
        fcntl(descriptors[0], F_SETFL, readFlags | O_NONBLOCK) == 0);
    uint64_t deadline = 5 * NSEC_PER_SEC;
    __block NSUInteger clockReads = 0;
    AQBrokerMonotonicClock expiresAfterPoll = ^uint64_t {
        clockReads += 1;
        return clockReads == 1 ? deadline - NSEC_PER_SEC : deadline;
    };
    NSData *payload = [@"must not be dispatched after expiry"
        dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BROKER_CHECK(!AQBrokerWriteAllUntilDeadline(
        descriptors[1], payload, deadline, expiresAfterPoll, &error));
    BROKER_CHECK(error.code == AQBrokerDeadlineExpired);
    BROKER_CHECK(clockReads >= 2);
    uint8_t byte = 0;
    ssize_t count = read(descriptors[0], &byte, sizeof(byte));
    BROKER_CHECK(count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK));
    close(descriptors[0]);
    close(descriptors[1]);
}

static void TestDeadlineWriteRestoresDescriptorFlagsOnFailure(void) {
    int descriptors[2] = {-1, -1};
    BROKER_CHECK(pipe(descriptors) == 0);
    int originalFlags = fcntl(descriptors[1], F_GETFL);
    BROKER_CHECK(originalFlags >= 0);
    int blockingFlags = originalFlags & ~O_NONBLOCK;
    BROKER_CHECK(fcntl(descriptors[1], F_SETFL, blockingFlags) == 0);
    uint64_t deadline = 5 * NSEC_PER_SEC;
    NSData *payload = [@"expired before write" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BROKER_CHECK(!AQBrokerWriteAllUntilDeadline(
        descriptors[1], payload, deadline, ^uint64_t { return deadline; }, &error));
    BROKER_CHECK(error.code == AQBrokerDeadlineExpired);
    BROKER_CHECK(fcntl(descriptors[1], F_GETFL) == blockingFlags);
    close(descriptors[0]);
    close(descriptors[1]);
}

static NSSet<NSString *> *TestReceiptDirectoryEntries(void) {
    NSError *error = nil;
    NSArray<NSString *> *entries = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:BrokerReceiptDirectory() error:&error];
    BROKER_CHECK(entries != nil && error == nil);
    return [NSSet setWithArray:entries ?: @[]];
}

static void TestNoReceiptArtifactsCreated(NSSet<NSString *> *before) {
    NSSet<NSString *> *after = TestReceiptDirectoryEntries();
    NSMutableSet<NSString *> *created = [after mutableCopy];
    [created minusSet:before];
    for (NSString *name in created) {
        BROKER_CHECK(![name hasSuffix:@".tmp"]);
        BROKER_CHECK(![name hasSuffix:@".receipt.json"]);
    }
}

static void TestDurableReceiptFailureIsUncertain(void) {
    BrokerTestDeadlineOverride = AQBrokerSystemClockNanoseconds() + 600ULL * NSEC_PER_SEC;
    for (NSUInteger successfulSyncs = 0; successfulSyncs < 3; ++successfulSyncs) {
        NSData *member = [@"durable receipt failure" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *manifest = TestManifest(@[member]);
        NSData *frame = TestFrame(manifest, member, NULL);
        NSError *error = nil;
        NSString *requestID = [NSString stringWithFormat:@"request-sync-failure-%lu",
                                                        (unsigned long)successfulSyncs];
        AQBrokerExportVerifier *verifier = TestExportVerifierWithSink(
            ^BOOL(__unused NSString *path, __unused NSData *bytes, __unused uint64_t offset) {
                return YES;
            }, manifest, @"session-1", 2, requestID, &error);
        BROKER_CHECK(verifier != nil);
        BROKER_CHECK([verifier consumeData:frame error:&error]);
        BROKER_CHECK(verifier.transportCompletion != nil);
        NSSet<NSString *> *receiptEntriesBefore = TestReceiptDirectoryEntries();
        if (successfulSyncs == 0) AQBrokerTestSetWriteFailureAfterBytes(32);
        else AQBrokerTestSetSyncFailureAfter(successfulSyncs, EIO);
        BROKER_CHECK(![verifier finishWithError:&error]);
        BROKER_CHECK(error.code == EIO);
        BROKER_CHECK(verifier.completion == nil);
        TestNoReceiptArtifactsCreated(receiptEntriesBefore);
AQBrokerTestSetSyncFailureAfter(NSUIntegerMax, EIO);
AQBrokerExportVerifier *retry = TestExportVerifierWithSink(
^BOOL(__unused NSString *path, __unused NSData *bytes, __unused uint64_t offset) {
return YES;
}, manifest, @"session-1", 2, requestID, &error);
BROKER_CHECK(retry != nil);
BROKER_CHECK([retry consumeData:frame error:&error]);
BROKER_CHECK([retry finishWithError:&error]);
BROKER_CHECK(retry.completion != nil);
    }
    BrokerTestDeadlineOverride = 0;
}

static void TestReceiptQueryUsesFreshDeadlineAfterOperationExpiry(void) {
    uint64_t now = AQBrokerSystemClockNanoseconds();
    uint64_t expiredOperationDeadline = now - 1;
    uint64_t queryDeadline = now + 4 * NSEC_PER_SEC;
    NSDictionary *binding = @{ @"deadline_ns": @(expiredOperationDeadline) };
    NSDictionary *request = @{
        @"operation": @"receipt_query",
        @"request_id": @"receipt-query-after-expiry",
        @"binding": binding,
        @"query_deadline_ns": @(queryDeadline),
    };
    BrokerReceiptQueryTransport *transport = [[BrokerReceiptQueryTransport alloc] init];
    transport.testReceiptReply = @{
        @"status": @"OK",
        @"request_id": @"receipt-query-after-expiry",
        @"completion": @{@"durable": @YES},
    };
    NSError *error = nil;
    BOOL responsePrinted = NO;
    BOOL fatalOutputFailure = NO;
    BOOL processed = AQBrokerProcessRequest(request, YES, nil, transport, nil, @[], nil,
        BrokerReceiptDirectory(), -1, &responsePrinted, &fatalOutputFailure, &error);

    BROKER_CHECK(processed);
    BROKER_CHECK(responsePrinted);
    BROKER_CHECK(!fatalOutputFailure);
    BROKER_CHECK(error == nil);
    BROKER_CHECK(transport.observedReceiptDeadlineNanoseconds == queryDeadline);
    NSDictionary *expectedControlRequest = @{
        @"operation": @"receipt_query",
        @"request_id": @"receipt-query-after-expiry",
        @"binding": binding,
    };
    BROKER_CHECK([transport.observedReceiptRequest isEqual:expectedControlRequest]);
    BROKER_CHECK([transport.observedReceiptRequest[@"binding"][@"deadline_ns"]
        isEqual:@(expiredOperationDeadline)]);
}

static void TestReceiptQueryRejectsExpiredAndUnboundedQueryDeadlines(void) {
    uint64_t now = AQBrokerSystemClockNanoseconds();
    NSArray<NSDictionary *> *invalidDeadlines = @[
        @{
            @"deadline": @(now - 1),
            @"error_code": @(AQBrokerDeadlineExpired),
        },
        @{
            @"deadline": @(now + 6 * NSEC_PER_SEC),
            @"error_code": @(AQBrokerInvalidRequest),
        },
    ];

    for (NSUInteger index = 0; index < invalidDeadlines.count; index++) {
        NSDictionary *invalidDeadline = invalidDeadlines[index];
        NSNumber *queryDeadline = invalidDeadline[@"deadline"] ?: @0;
        NSNumber *expectedErrorCode = invalidDeadline[@"error_code"] ?: @0;
        NSString *requestID = [NSString stringWithFormat:@"receipt-query-invalid-deadline-%lu",
            (unsigned long)index];
        NSDictionary *request = @{
            @"operation": @"receipt_query",
            @"request_id": requestID,
            @"binding": @{@"deadline_ns": @(now - 1)},
            @"query_deadline_ns": queryDeadline,
        };
        BrokerReceiptQueryTransport *transport = [[BrokerReceiptQueryTransport alloc] init];
        NSError *error = nil;
        BOOL responsePrinted = NO;
        BOOL fatalOutputFailure = NO;
        BOOL processed = AQBrokerProcessRequest(request, YES, nil, transport, nil, @[], nil,
            BrokerReceiptDirectory(), -1, &responsePrinted, &fatalOutputFailure, &error);

        BROKER_CHECK(!processed);
        BROKER_CHECK(error.code == expectedErrorCode.integerValue);
        BROKER_CHECK(transport.observedReceiptRequest == nil);
        BROKER_CHECK(!responsePrinted);
        BROKER_CHECK(!fatalOutputFailure);
    }
}

static void TestMismatchedReceiptUsesStableErrorWithStaleErrno(void) {
    BrokerTestDeadlineOverride = AQBrokerSystemClockNanoseconds() + 600ULL * NSEC_PER_SEC;
    NSData *member = [@"receipt mismatch" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    NSError *error = nil;
    NSString *requestID = @"request-mismatched-receipt";
    AQBrokerExportVerifier *initial = TestExportVerifierWithSink(
        ^BOOL(__unused NSString *path, __unused NSData *bytes, __unused uint64_t offset) {
            return YES;
        }, manifest, @"session-1", 2, requestID, &error);
    BROKER_CHECK(initial != nil);
    BROKER_CHECK([initial consumeData:frame error:&error]);
    BROKER_CHECK([initial finishWithError:&error]);
    NSString *receiptPath = initial.completion[@"receipt_path"];
    BROKER_CHECK(receiptPath != nil);
    NSData *tamperedReceipt = [@"not the durable receipt" dataUsingEncoding:NSUTF8StringEncoding];
    BROKER_CHECK([tamperedReceipt writeToFile:receiptPath atomically:NO]);

    AQBrokerExportVerifier *retry = TestExportVerifierWithSink(
        ^BOOL(__unused NSString *path, __unused NSData *bytes, __unused uint64_t offset) {
            return YES;
        }, manifest, @"session-1", 2, requestID, &error);
    BROKER_CHECK(retry != nil);
    BROKER_CHECK([retry consumeData:frame error:&error]);
    errno = EPERM;
    BROKER_CHECK(![retry finishWithError:&error]);
    BROKER_CHECK(error.domain == NSPOSIXErrorDomain && error.code == EIO);
    BrokerTestDeadlineOverride = 0;
}

static void TestReceiptDeadlineFailureCanRetryWithoutAcknowledgement(void) {
    NSData *member = [@"receipt deadline failure" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSData *frame = TestFrame(manifest, member, NULL);
    __block BOOL expireDuringFinish = NO;
    __block NSUInteger finishClockReads = 0;
    uint64_t deadline = 100;
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = [[AQBrokerExportVerifier alloc]
        initWithSink:^BOOL(__unused NSString *path, __unused NSData *bytes,
                           __unused uint64_t offset) { return YES; }
        expectedSessionID:@"session-1"
        expectedGeneration:2
        expectedManifestSHA256:(NSString *)AQDigest(@"", manifest, NULL)
        authorizationSHA256:[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0]
        approvedManifest:manifest
        requestID:@"request-receipt-deadline"
        deadlineNanoseconds:deadline
        clock:^uint64_t {
            if (!expireDuringFinish) return 99;
            return ++finishClockReads <= 2 ? 99 : 101;
        }
        receiptDirectory:BrokerReceiptDirectory()
        error:&error];
    BROKER_CHECK(verifier != nil);
    BROKER_CHECK([verifier consumeData:frame error:&error]);
    NSSet<NSString *> *receiptEntriesBefore = TestReceiptDirectoryEntries();
    expireDuringFinish = YES;
    BROKER_CHECK(![verifier finishWithError:&error]);
    BROKER_CHECK(verifier.completion == nil);
    TestNoReceiptArtifactsCreated(receiptEntriesBefore);

    AQBrokerExportVerifier *retry = TestExportVerifierWithSink(
        ^BOOL(__unused NSString *path, __unused NSData *bytes, __unused uint64_t offset) {
            return YES;
        }, manifest, @"session-1", 2, @"request-receipt-deadline", &error);
    BROKER_CHECK(retry != nil);
    BROKER_CHECK([retry consumeData:frame error:&error]);
    BROKER_CHECK([retry finishWithError:&error]);
    BROKER_CHECK(retry.completion != nil);
}

static void TestManifestMustMatchSignedDigest(void) {
    NSData *member = [@"manifest authority" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *manifest = TestManifest(@[member]);
    NSError *error = nil;
    AQBrokerExportVerifier *verifier = [[AQBrokerExportVerifier alloc]
        initWithSink:^BOOL(NSString *path, NSData *bytes, uint64_t offset) {
            (void)path; (void)bytes; (void)offset; return YES;
        }
        expectedSessionID:@"session-1"
        expectedGeneration:2
        expectedManifestSHA256:[@"f" stringByPaddingToLength:64 withString:@"f" startingAtIndex:0]
        authorizationSHA256:[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0]
        approvedManifest:manifest
        requestID:@"request-manifest-mismatch"
        deadlineNanoseconds:AQBrokerSystemClockNanoseconds() + 60 * NSEC_PER_SEC
        clock:^uint64_t { return AQBrokerSystemClockNanoseconds(); }
        receiptDirectory:BrokerReceiptDirectory()
        error:&error];
    BROKER_CHECK(verifier == nil);
    BROKER_CHECK(error.code == AQBrokerBindingMismatch);
}

static void TestReplyRaceClosesExportDescriptor(void) {
    int descriptors[2] = {-1, -1};
    BROKER_CHECK(pipe(descriptors) == 0);
    AQBrokerReplyCapture *timedOut = [[AQBrokerReplyCapture alloc] init];
    BROKER_CHECK([timedOut abandon]);
    int lateFD = dup(descriptors[0]);
    BROKER_CHECK(lateFD >= 0);
    BROKER_CHECK(![timedOut finishWithResponse:@{@"status": @"OK"}
                                         error:nil exportFD:lateFD]);
    BROKER_CHECK(fcntl(lateFD, F_GETFD) < 0 && errno == EBADF);

    AQBrokerReplyCapture *winner = [[AQBrokerReplyCapture alloc] init];
    int installedFD = dup(descriptors[0]);
    BROKER_CHECK(installedFD >= 0);
    BROKER_CHECK([winner finishWithResponse:@{@"status": @"OK"}
                                      error:nil exportFD:installedFD]);
    BROKER_CHECK(![winner abandon]);
    BROKER_CHECK(fcntl(installedFD, F_GETFD) >= 0);
    close(installedFD);
    close(descriptors[0]);
    close(descriptors[1]);
}

static void TestMutationOutputFailureRetainsUncertainty(void) {
    BrokerFailingResponseTransport *transport = [[BrokerFailingResponseTransport alloc] init];
    transport.testResponse = @{@"status": @"OK", @"request_id": @"stage-output",
                               @"result": @{@"invalid": [NSDate date]}};
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return AQBrokerSystemClockNanoseconds(); }
        enforceOrdering:NO];
    uint64_t deadline = AQBrokerSystemClockNanoseconds() + 60 * NSEC_PER_SEC;
    NSDictionary *request = BrokerSignedRequest(@"stage", @"stage-output", 1, deadline,
        @"session-1", @"connection-1", @"owner-key-1");
    NSError *error = nil;
    BOOL responsePrinted = NO, fatalOutputFailure = NO;
    BROKER_CHECK(!AQBrokerProcessRequest(request, NO, nil, transport, session, @[],
                                          nil, BrokerReceiptDirectory(), -1, &responsePrinted,
                                          &fatalOutputFailure, &error));
    BROKER_CHECK(fatalOutputFailure);
    BROKER_CHECK(session.requiresFreshAuthentication);
    uint64_t token = 0;
    NSDictionary *replay = BrokerSignedRequest(@"stage", @"stage-replay", 2, deadline,
        @"session-1", @"connection-1", @"owner-key-1");
    BROKER_CHECK(![session beginRequest:replay token:&token error:&error]);
    BROKER_CHECK(error.code == AQBrokerUncertainEffect);
}

static void TestMutationWriteFailureRetainsUncertainty(void) {
    BrokerFailingResponseTransport *transport = [[BrokerFailingResponseTransport alloc] init];
    transport.testResponse = @{@"status": @"OK", @"request_id": @"stage-write",
                               @"result": @{@"accepted": @YES}};
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return AQBrokerSystemClockNanoseconds(); }
        enforceOrdering:NO];
    uint64_t deadline = AQBrokerSystemClockNanoseconds() + 60 * NSEC_PER_SEC;
    NSDictionary *request = BrokerSignedRequest(@"stage", @"stage-write", 1, deadline,
        @"session-1", @"connection-1", @"owner-key-1");
    int savedStdout = dup(STDOUT_FILENO);
    BROKER_CHECK(savedStdout >= 0);
    close(STDOUT_FILENO);
    NSError *error = nil;
    BOOL responsePrinted = NO, fatalOutputFailure = NO;
    BROKER_CHECK(!AQBrokerProcessRequest(request, NO, nil, transport, session, @[],
                                          nil, BrokerReceiptDirectory(), -1, &responsePrinted,
                                          &fatalOutputFailure, &error));
    dup2(savedStdout, STDOUT_FILENO);
    close(savedStdout);
    BROKER_CHECK(error.code == EBADF);
    BROKER_CHECK(fatalOutputFailure);
    BROKER_CHECK(session.requiresFreshAuthentication);
}

static void TestMutationClosedPipeRetainsUncertainty(void) {
    BrokerFailingResponseTransport *transport = [[BrokerFailingResponseTransport alloc] init];
    transport.testResponse = @{@"status": @"OK", @"request_id": @"stage-pipe",
                               @"result": @{@"accepted": @YES}};
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return AQBrokerSystemClockNanoseconds(); }
        enforceOrdering:NO];
    uint64_t deadline = AQBrokerSystemClockNanoseconds() + 60 * NSEC_PER_SEC;
    NSDictionary *request = BrokerSignedRequest(@"stage", @"stage-pipe", 1, deadline,
        @"session-1", @"connection-1", @"owner-key-1");

    int savedStdout = dup(STDOUT_FILENO);
    int descriptors[2] = {-1, -1};
    BROKER_CHECK(savedStdout >= 0);
    BROKER_CHECK(pipe(descriptors) == 0);
    close(descriptors[0]);
    BROKER_CHECK(dup2(descriptors[1], STDOUT_FILENO) == STDOUT_FILENO);
    close(descriptors[1]);
    BROKER_CHECK(AQBrokerConfigureSIGPIPE());

    NSError *error = nil;
    BOOL responsePrinted = NO;
    BOOL fatalOutputFailure = NO;
    BROKER_CHECK(!AQBrokerProcessRequest(request, NO, nil, transport, session, @[],
                                          nil, BrokerReceiptDirectory(), -1, &responsePrinted,
                                          &fatalOutputFailure, &error));
    BROKER_CHECK(dup2(savedStdout, STDOUT_FILENO) == STDOUT_FILENO);
    close(savedStdout);
    BROKER_CHECK(error.code == EPIPE);
    BROKER_CHECK(fatalOutputFailure);
    BROKER_CHECK(session.requiresFreshAuthentication);
}

static NSDictionary *BrokerSignedRequestWithSourcePaths(
    id sourcePaths, NSString *requestID, uint64_t sequence, uint64_t deadline) {
    NSMutableDictionary *request = [BrokerSignedRequest(
        @"stage", requestID, sequence, deadline, @"session-1", @"connection-1",
        @"owner-key-1") mutableCopy];
    request[@"source_paths"] = sourcePaths;
    return request;
}

static void TestPrivateInputFilesRejectSharedPermissions(void) {
    NSString *unique = [NSString stringWithFormat:@"broker-private-%@", NSUUID.UUID.UUIDString];
    NSString *path = [BrokerReceiptDirectory() stringByAppendingPathComponent:unique];
    NSData *contents = [@"private broker input" dataUsingEncoding:NSUTF8StringEncoding];
    BROKER_CHECK(BrokerCreateForeignFile(path, contents));

    NSError *error = nil;
    NSData *readData = AQBrokerReadPrivateFile(path, geteuid(), &error);
    BROKER_CHECK([readData isEqualToData:contents]);
    BROKER_CHECK(AQBrokerReadPrivateFile(
        path, geteuid() == 0 ? 1 : 0, &error) == nil);

    for (NSNumber *mode in @[@0644, @0640, @0604]) {
        BROKER_CHECK(chmod(path.fileSystemRepresentation, mode.unsignedShortValue) == 0);
        error = nil;
        BROKER_CHECK(AQBrokerReadPrivateFile(path, geteuid(), &error) == nil);
    }
    BROKER_CHECK(chmod(path.fileSystemRepresentation, 0600) == 0);

    NSString *hardLink = [path stringByAppendingString:@".hardlink"];
    BROKER_CHECK(link(path.fileSystemRepresentation, hardLink.fileSystemRepresentation) == 0);
    BROKER_CHECK(AQBrokerReadPrivateFile(path, geteuid(), &error) == nil);
    BROKER_CHECK(unlink(hardLink.fileSystemRepresentation) == 0);

    NSString *symbolicLink = [path stringByAppendingString:@".symlink"];
    BROKER_CHECK(symlink(path.fileSystemRepresentation,
                         symbolicLink.fileSystemRepresentation) == 0);
    BROKER_CHECK(AQBrokerReadPrivateFile(symbolicLink, geteuid(), &error) == nil);
    BROKER_CHECK(unlink(symbolicLink.fileSystemRepresentation) == 0);

    NSString *directory = [path stringByAppendingString:@".directory"];
    BROKER_CHECK(mkdir(directory.fileSystemRepresentation, 0700) == 0);
    BROKER_CHECK(AQBrokerReadPrivateFile(directory, geteuid(), &error) == nil);
    BROKER_CHECK(rmdir(directory.fileSystemRepresentation) == 0);
    BROKER_CHECK(unlink(path.fileSystemRepresentation) == 0);
}

static void TestPrivateInputFifoRejectedWithoutBlocking(void) {
    NSString *unique = [NSString stringWithFormat:@"broker-fifo-%@", NSUUID.UUID.UUIDString];
    NSString *path = [BrokerReceiptDirectory() stringByAppendingPathComponent:unique];
    BROKER_CHECK(mkfifo(path.fileSystemRepresentation, 0600) == 0);
    alarm(2);
    NSError *error = nil;
    NSData *data = AQBrokerReadPrivateFile(path, geteuid(), &error);
    alarm(0);
    BROKER_CHECK(data == nil);
    BROKER_CHECK(unlink(path.fileSystemRepresentation) == 0);
}

static void TestSourcePathsMustBeBoundedStrings(void) {
    BrokerFailingResponseTransport *transport = [[BrokerFailingResponseTransport alloc] init];
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return AQBrokerSystemClockNanoseconds(); }
        enforceOrdering:NO];
    uint64_t deadline = AQBrokerSystemClockNanoseconds() + 60 * NSEC_PER_SEC;
    NSArray *malformed = @[
        @"not-an-array",
        NSNull.null,
        @17,
        @[@"valid", @17],
    ];
    for (id sourcePaths in malformed) {
        NSError *error = nil;
        BOOL responsePrinted = YES;
        BOOL fatalOutputFailure = YES;
        NSDictionary *request = BrokerSignedRequestWithSourcePaths(
            sourcePaths, @"malformed-source-paths", 1, deadline);
        BROKER_CHECK(!AQBrokerProcessRequest(
            request, NO, nil, transport, session, @[], nil, BrokerReceiptDirectory(), -1,
            &responsePrinted, &fatalOutputFailure, &error));
        BROKER_CHECK([error.localizedDescription isEqual:@"SOURCE_BINDING_INVALID"]);
        BROKER_CHECK(!responsePrinted);
        BROKER_CHECK(!fatalOutputFailure);
    }

    NSMutableArray<NSString *> *tooManyPaths = [NSMutableArray array];
    for (NSUInteger index = 0; index <= AQServiceMaximumSourceDescriptors; ++index) {
        [tooManyPaths addObject:[NSString stringWithFormat:@"source-%lu", (unsigned long)index]];
    }
    NSError *tooManyError = nil;
    NSDictionary *tooManyRequest = BrokerSignedRequestWithSourcePaths(
        tooManyPaths, @"too-many-source-paths", 1, deadline);
    BROKER_CHECK(!AQBrokerProcessRequest(
        tooManyRequest, NO, nil, transport, session, @[], nil, BrokerReceiptDirectory(), -1,
        NULL, NULL, &tooManyError));
    BROKER_CHECK([tooManyError.localizedDescription isEqual:@"SOURCE_BINDING_INVALID"]);
}

static BOOL BrokerSelfCheckPolicyLoader(AQInstallationPolicy **policy, NSError **error) {
    if (error != NULL) *error = nil;
    if (policy != NULL) *policy = (AQInstallationPolicy *)[[NSObject alloc] init];
    return YES;
}

static BOOL BrokerSelfCheckPeerAPIProbe(NSError **error) {
    if (error != NULL) *error = nil;
    return YES;
}

static BOOL BrokerSelfCheckServiceIdentityProbe(AQInstallationPolicy *policy, NSError **error) {
    (void)policy;
    if (error != NULL) *error = nil;
    return YES;
}

static void TestSelfCheckReadyWriteFailureReturnsNonzero(void) {
    BOOL (*savedPolicyLoader)(AQInstallationPolicy **, NSError **) =
        AQBrokerSelfCheckPolicyLoader;
    BOOL (*savedPeerAPIProbe)(NSError **) = AQBrokerSelfCheckPeerAPIProbe;
    BOOL (*savedServiceIdentityProbe)(AQInstallationPolicy *, NSError **) =
        AQBrokerSelfCheckServiceIdentityProbe;
    AQBrokerSelfCheckPolicyLoader = BrokerSelfCheckPolicyLoader;
    AQBrokerSelfCheckPeerAPIProbe = BrokerSelfCheckPeerAPIProbe;
    AQBrokerSelfCheckServiceIdentityProbe = BrokerSelfCheckServiceIdentityProbe;
    BROKER_CHECK(AQBrokerConfigureSIGPIPE());

    int savedStdout = dup(STDOUT_FILENO);
    int descriptors[2] = {-1, -1};
    BROKER_CHECK(savedStdout >= 0);
    BROKER_CHECK(pipe(descriptors) == 0);
    close(descriptors[0]);
    BROKER_CHECK(dup2(descriptors[1], STDOUT_FILENO) == STDOUT_FILENO);
    close(descriptors[1]);
    int result = AQBrokerSelfCheck();
    BROKER_CHECK(dup2(savedStdout, STDOUT_FILENO) == STDOUT_FILENO);
    close(savedStdout);

    AQBrokerSelfCheckPolicyLoader = savedPolicyLoader;
    AQBrokerSelfCheckPeerAPIProbe = savedPeerAPIProbe;
    AQBrokerSelfCheckServiceIdentityProbe = savedServiceIdentityProbe;
    BROKER_CHECK(result == 2);
}

static void TestSelfCheckReportsNotReadyUntilXPCProof(void) {
    BOOL (*savedPolicyLoader)(AQInstallationPolicy **, NSError **) = AQBrokerSelfCheckPolicyLoader;
    BOOL (*savedPeerAPIProbe)(NSError **) = AQBrokerSelfCheckPeerAPIProbe;
    BOOL (*savedServiceIdentityProbe)(AQInstallationPolicy *, NSError **) =
        AQBrokerSelfCheckServiceIdentityProbe;
    AQBrokerSelfCheckPolicyLoader = BrokerSelfCheckPolicyLoader;
    AQBrokerSelfCheckPeerAPIProbe = BrokerSelfCheckPeerAPIProbe;
    AQBrokerSelfCheckServiceIdentityProbe = BrokerSelfCheckServiceIdentityProbe;

    int savedStdout = dup(STDOUT_FILENO);
    int descriptors[2] = {-1, -1};
    BROKER_CHECK(savedStdout >= 0);
    BROKER_CHECK(pipe(descriptors) == 0);
    BROKER_CHECK(dup2(descriptors[1], STDOUT_FILENO) == STDOUT_FILENO);
    close(descriptors[1]);
    int result = AQBrokerSelfCheck();
    BROKER_CHECK(dup2(savedStdout, STDOUT_FILENO) == STDOUT_FILENO);
    close(savedStdout);

    char output[256] = {0};
    ssize_t count = read(descriptors[0], output, sizeof(output) - 1);
    close(descriptors[0]);
    BROKER_CHECK(result == 2);
    BROKER_CHECK(count > 0);
    BROKER_CHECK(strstr(output, "\"status\":\"NOT_READY\"") != NULL);
    BROKER_CHECK(strstr(output, "AWAITING_XPC_DEPENDENCY_PROOF") != NULL);

    AQBrokerSelfCheckPolicyLoader = savedPolicyLoader;
    AQBrokerSelfCheckPeerAPIProbe = savedPeerAPIProbe;
    AQBrokerSelfCheckServiceIdentityProbe = savedServiceIdentityProbe;
}

static void TestBrokerProcessSurvivesClosedStdoutPipe(void) {
    NSString *testBinary = NSProcessInfo.processInfo.arguments.firstObject;
    NSString *brokerBinary = [[testBinary stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker"];
    BROKER_CHECK([[NSFileManager defaultManager] isExecutableFileAtPath:brokerBinary]);

    int descriptors[2] = {-1, -1};
    BROKER_CHECK(pipe(descriptors) == 0);
    pid_t child = fork();
    BROKER_CHECK(child >= 0);
    if (child == 0) {
        close(descriptors[0]);
        if (dup2(descriptors[1], STDOUT_FILENO) < 0) _exit(127);
        close(descriptors[1]);
        char *const arguments[] = {(char *)brokerBinary.fileSystemRepresentation,
                                   (char *)"--self-check", NULL};
        execv(brokerBinary.fileSystemRepresentation, arguments);
        _exit(127);
    }

    close(descriptors[0]);
    close(descriptors[1]);
    int status = 0;
    BROKER_CHECK(waitpid(child, &status, 0) == child);
    BROKER_CHECK(WIFEXITED(status));
    BROKER_CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 2);
}

static void TestOwnerExportPrepareJournalDispatchOrder(void) {
    NSDictionary *helloResponse = @{
        @"connection_id": @"connection-1",
        @"session_id": @"session-1",
        @"service_boot_id": @"boot-1",
    };
    AQBrokerOwnerExportContinuation *continuation =
        [[AQBrokerOwnerExportContinuation alloc]
            initWithHelloResponse:helloResponse
            installationID:@"installation-1"
            brokerRevision:@"broker-1"
            ownerKeyID:@"owner-key-1"
            authorizationSHA256:@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"];
    BROKER_CHECK(continuation != nil);
    NSDictionary *hello = @{
        @"operation": @"hello",
        @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1",
        @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
        @"connection_id": @"connection-1",
        @"session_id": @"session-1",
    };
    NSDictionary *(^request)(NSString *) = ^NSDictionary *(NSString *operation) {
        return @{
            @"operation": operation,
            @"request_id": [operation isEqual:@"export"] ? @"request-export" : operation,
            @"sequence": @3,
            @"deadline_ns": @1000,
            @"manifest_sha256": @"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            @"installation_id": @"installation-1",
            @"service_boot_id": @"boot-1",
            @"broker_revision": @"broker-1",
            @"owner_key_id": @"owner-key-1",
            @"connection_id": @"connection-1",
            @"session_id": @"session-1",
            @"freshness_envelope": @"e30=",
            @"freshness_signature": @"synthetic-owner-signature",
            @"consent_signature": @"synthetic-owner-signature",
        };
    };
    NSDictionary *admit = request(@"admit");
    NSDictionary *stage = request(@"stage");
    NSDictionary *export = request(@"export");
    NSDictionary *attempt = @{
        @"request_id": @"request-export",
        @"operation": @"export",
        @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1",
        @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
        @"connection_id": @"connection-1",
        @"session_id": @"session-1",
        @"authorization_sha256": @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        @"sequence": @3,
        @"deadline_ns": @1000,
        @"manifest_sha256": @"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        @"request_sha256": @"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        @"generation": @1,
        @"members": @[],
    };
    NSError *error = nil;
    BROKER_CHECK(([continuation prepareAttempt:attempt
                                       workflow:@[hello, admit, stage, export]
                                          error:&error]));
    BROKER_CHECK(![continuation beginDispatchOperation:@"admit" request:admit error:&error]);
    BROKER_CHECK([continuation acknowledgeJournalAttemptSHA256:continuation.attemptSHA256
                                                        error:&error]);
    BROKER_CHECK([continuation beginDispatchOperation:@"admit" request:admit error:&error]);
    BROKER_CHECK([continuation completeDispatchOperation:@"admit" error:&error]);
    BROKER_CHECK([continuation beginDispatchOperation:@"stage" request:stage error:&error]);
    BROKER_CHECK([continuation completeDispatchOperation:@"stage" error:&error]);
    BROKER_CHECK([continuation beginDispatchOperation:@"export" request:export error:&error]);
    BROKER_CHECK([continuation completeDispatchOperation:@"export" error:&error]);
    BROKER_CHECK(continuation.dispatchComplete);
}

static void TestInvalidWorkflowDoesNotPromptForConsentSignature(void) {
    __block uint64_t now = 100;
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return now; }];
    NSError *error = nil;
    uint64_t helloToken = 0;
    NSDictionary *helloRequest = BrokerHelloRequest(@"hello-consent-order", 1, 1000);
    BROKER_CHECK([session beginRequest:helloRequest token:&helloToken error:&error]);
    BROKER_CHECK([session acceptResponseForToken:helloToken
        response:BrokerHelloResponse(@"hello-consent-order", @"session-1", @"connection-1")
        error:&error]);
    BROKER_CHECK([session completeRequestForToken:helloToken outcomeKnown:YES error:&error]);

    NSMutableDictionary *hello = [@{
        @"operation": @"hello",
        @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1",
        @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
    } mutableCopy];
    NSData *authorization = [@"authorization" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *authorizationSHA256 = BrokerDigest(authorization);
    NSDictionary *admitClaims = @{@"request_sha256": [@"a" stringByPaddingToLength:64
        withString:@"a" startingAtIndex:0]};
    NSDictionary *stageClaims = @{@"request_sha256": [@"b" stringByPaddingToLength:64
        withString:@"b" startingAtIndex:0]};
    NSDictionary *invalidExportClaims = @{
        @"request_sha256": [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0],
        @"unexpected_claim": @"must_be_rejected_before_consent"
    };
    NSString *manifestSHA256 = [@"d" stringByPaddingToLength:64 withString:@"d" startingAtIndex:0];
    NSString *approvalSHA256 = [@"e" stringByPaddingToLength:64 withString:@"e" startingAtIndex:0];
    NSString *planSHA256 = [@"f" stringByPaddingToLength:64 withString:@"f" startingAtIndex:0];
    NSString *rulesSHA256 = [@"1" stringByPaddingToLength:64 withString:@"1" startingAtIndex:0];
    [hello addEntriesFromDictionary:@{
        @"nonce": (NSString *)helloRequest[@"nonce"], @"grant_id": @"grant-1",
        @"authorization_sha256": authorizationSHA256, @"approval_sha256": approvalSHA256,
        @"manifest_sha256": manifestSHA256, @"plan_sha256": planSHA256,
        @"rules_sha256": rulesSHA256, @"operations": @[@"stage", @"export"],
        @"deadline_ns": @1000, @"store_deadline_ticks": @2000,
        @"host_reserve_bytes": @0, @"destination_reserve_bytes": @0,
        @"cleanup_authorized": @NO
    }];
    NSArray *templates = @[
        @{@"operation": @"admit", @"request_id": @"request-admit", @"sequence": @1,
          @"deadline_ns": @1000, @"nonce": @"nonce-admit", @"manifest_sha256": manifestSHA256,
          @"freshness_claims": admitClaims, @"documents_b64": @{}},
        @{@"operation": @"stage", @"request_id": @"request-stage", @"sequence": @2,
          @"deadline_ns": @1000, @"nonce": @"nonce-stage", @"manifest_sha256": manifestSHA256,
          @"freshness_claims": stageClaims},
        @{@"operation": @"export", @"request_id": @"request-export", @"sequence": @3,
          @"deadline_ns": @1000, @"nonce": @"nonce-export", @"manifest_sha256": manifestSHA256,
          @"generation": @1, @"members": @[], @"freshness_claims": invalidExportClaims},
    ];
    NSDictionary *consentEnvelope = @{
        @"schema_version": @1,
        @"owner_key_id": @"owner-key-1",
        @"broker_revision": @"broker-1",
        @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1",
        @"session_id": @"session-1",
        @"connection_id": @"connection-1",
        @"challenge": @"challenge-1",
        @"nonce": helloRequest[@"nonce"] ?: @"nonce-hello",
        @"grant_id": @"grant-1",
        @"authorization_sha256": authorizationSHA256,
        @"approval_sha256": approvalSHA256,
        @"manifest_sha256": manifestSHA256,
        @"plan_sha256": planSHA256,
        @"rules_sha256": rulesSHA256,
        @"operations": @[@"stage", @"export"],
        @"deadline_ns": @1000,
        @"store_deadline_ticks": @2000,
        @"host_reserve_bytes": @0,
        @"destination_reserve_bytes": @0,
        @"cleanup_authorized": @NO,
    };
    NSDictionary *request = @{
        @"consent_envelope": consentEnvelope,
        @"workflow_templates": templates,
    };
    NSMutableArray *invalidSequenceTemplates = [templates mutableCopy];
    NSMutableDictionary *invalidStage = [templates[1] mutableCopy];
    invalidStage[@"sequence"] = @1;
    invalidSequenceTemplates[1] = invalidStage;
    NSDictionary *invalidSequenceRequest = @{
        @"consent_envelope": consentEnvelope,
        @"workflow_templates": invalidSequenceTemplates,
    };
    NSMutableDictionary *incompleteConsent = [consentEnvelope mutableCopy];
    [incompleteConsent removeObjectForKey:@"challenge"];
    NSDictionary *incompleteConsentRequest = @{
        @"consent_envelope": incompleteConsent,
        @"workflow_templates": templates,
    };
    AQBrokerTestOwnerSignatureRequestCount = 0;
    AQBrokerTestUseSyntheticOwnerSignature = YES;
    for (NSDictionary *invalidRequest in @[request, invalidSequenceRequest, incompleteConsentRequest]) {
        error = nil;
        NSDictionary *prepared = AQBrokerPrepareOwnerExport(
            invalidRequest, hello, (AQInstallationPolicy *)(id)[NSObject new], session,
            authorization, &error);
        BROKER_CHECK(prepared == nil);
        BROKER_CHECK(error.code == AQBrokerInvalidRequest);
        BROKER_CHECK(AQBrokerTestOwnerSignatureRequestCount == 0);
    }
    AQBrokerTestUseSyntheticOwnerSignature = NO;
}

static void TestOwnerExportPreparationRequiresOwnerAuthority(void) {
    NSDictionary *helloResponse = @{
        @"connection_id": @"connection-1",
        @"session_id": @"session-1",
        @"service_boot_id": @"boot-1",
    };
    AQBrokerOwnerExportContinuation *continuation =
        [[AQBrokerOwnerExportContinuation alloc]
            initWithHelloResponse:helloResponse
            installationID:@"installation-1"
            brokerRevision:@"broker-1"
            ownerKeyID:@""
            authorizationSHA256:@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"];
    BROKER_CHECK(continuation == nil);
}

static void TestInvalidAdmissionDocumentsDoNotPromptForConsentSignature(void) {
    __block uint64_t now = 100;
    AQBrokerSequentialSession *session = [[AQBrokerSequentialSession alloc]
        initWithClock:^uint64_t { return now; }];
    NSError *error = nil;
    NSDictionary *sessionHello = BrokerHelloRequest(@"hello-invalid-documents", 1, 1000);
    uint64_t helloToken = 0;
    BROKER_CHECK([session beginRequest:sessionHello token:&helloToken error:&error]);
    BROKER_CHECK([session acceptResponseForToken:helloToken
        response:BrokerHelloResponse(@"hello-invalid-documents", @"session-1", @"connection-1")
        error:&error]);
    BROKER_CHECK([session completeRequestForToken:helloToken outcomeKnown:YES error:&error]);

    NSString *manifestSHA256 = [@"d" stringByPaddingToLength:64
        withString:@"d" startingAtIndex:0];
    NSDictionary *plan = @{@"schema_version": @1, @"rules": @{}};
    NSData *planBytes = AQCanonicalJSON(plan, NULL) ?: [NSData data];
    NSString *planSHA256 = BrokerDigest(planBytes);
    NSData *rulesBytes = AQCanonicalJSON(plan[@"rules"] ?: @{}, NULL) ?: [NSData data];
    NSString *rulesSHA256 = BrokerDigest(rulesBytes);
    NSDictionary *authorizationDocument = @{
        @"authorization_id": @"synthetic-owner-authorization",
        @"fixture_manifest_sha256": manifestSHA256,
        @"plan": @{@"plan_sha256": planSHA256, @"rules_sha256": rulesSHA256},
    };
    NSData *authorization = AQCanonicalJSON(authorizationDocument, NULL);
    NSString *authorizationSHA256 = BrokerDigest(authorization);
    NSString *approvalSHA256 = [@"e" stringByPaddingToLength:64
        withString:@"e" startingAtIndex:0];
    NSDictionary *hello = @{
        @"operation": @"hello",
        @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1",
        @"broker_revision": @"broker-1",
        @"owner_key_id": @"owner-key-1",
        @"nonce": sessionHello[@"nonce"] ?: @"nonce-hello",
        @"grant_id": @"grant-1",
        @"authorization_sha256": authorizationSHA256,
        @"approval_sha256": approvalSHA256,
        @"manifest_sha256": manifestSHA256,
        @"plan_sha256": planSHA256,
        @"rules_sha256": rulesSHA256,
        @"operations": @[@"stage", @"export"],
        @"deadline_ns": @1000,
        @"store_deadline_ticks": @2000,
        @"host_reserve_bytes": @0,
        @"destination_reserve_bytes": @0,
        @"cleanup_authorized": @NO,
    };
    NSDictionary *documents = @{
        @"consent": [@"consent" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data],
        @"signature": [@"signature" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data],
        @"manifest": [@"not-json" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data],
        @"plan": planBytes,
        @"oracles": @[],
        @"evidence": @[],
    };
    NSMutableDictionary *encodedDocuments = [NSMutableDictionary dictionary];
    for (NSString *key in documents) {
        id value = documents[key];
        encodedDocuments[key] = [value isKindOfClass:NSData.class]
            ? [value base64EncodedStringWithOptions:0] : value;
    }
    NSDictionary *admitClaims = @{@"request_sha256": [@"a" stringByPaddingToLength:64
        withString:@"a" startingAtIndex:0]};
    NSDictionary *stageClaims = @{@"request_sha256": [@"b" stringByPaddingToLength:64
        withString:@"b" startingAtIndex:0]};
    NSDictionary *exportClaims = @{@"request_sha256": [@"c" stringByPaddingToLength:64
        withString:@"c" startingAtIndex:0]};
    NSArray *templates = @[
        @{@"operation": @"admit", @"request_id": @"request-admit", @"sequence": @1,
          @"deadline_ns": @1000, @"nonce": @"nonce-admit",
          @"manifest_sha256": manifestSHA256, @"freshness_claims": admitClaims,
          @"documents_b64": encodedDocuments},
        @{@"operation": @"stage", @"request_id": @"request-stage", @"sequence": @2,
          @"deadline_ns": @1000, @"nonce": @"nonce-stage",
          @"manifest_sha256": manifestSHA256, @"freshness_claims": stageClaims},
        @{@"operation": @"export", @"request_id": @"request-export", @"sequence": @3,
          @"deadline_ns": @1000, @"nonce": @"nonce-export",
          @"manifest_sha256": manifestSHA256, @"generation": @1,
          @"members": @[], @"freshness_claims": exportClaims},
    ];
    NSDictionary *consentEnvelope = @{
        @"schema_version": @1, @"owner_key_id": @"owner-key-1",
        @"broker_revision": @"broker-1", @"installation_id": @"installation-1",
        @"service_boot_id": @"boot-1", @"session_id": @"session-1",
        @"connection_id": @"connection-1", @"challenge": @"challenge-1",
        @"nonce": sessionHello[@"nonce"] ?: @"nonce-hello", @"grant_id": @"grant-1",
        @"authorization_sha256": authorizationSHA256,
        @"approval_sha256": approvalSHA256, @"manifest_sha256": manifestSHA256,
        @"plan_sha256": planSHA256, @"rules_sha256": rulesSHA256,
        @"operations": @[@"stage", @"export"], @"deadline_ns": @1000,
        @"store_deadline_ticks": @2000, @"host_reserve_bytes": @0,
        @"destination_reserve_bytes": @0, @"cleanup_authorized": @NO,
    };
    NSDictionary *request = @{
        @"consent_envelope": consentEnvelope,
        @"workflow_templates": templates,
    };

    AQBrokerTestOwnerSignatureRequestCount = 0;
    AQBrokerTestUseSyntheticOwnerSignature = YES;
    NSDictionary *prepared = AQBrokerPrepareOwnerExport(
        request, hello, (AQInstallationPolicy *)(id)[NSObject new], session,
        authorization, &error);
    BROKER_CHECK(prepared == nil);
    BROKER_CHECK(AQBrokerTestOwnerSignatureRequestCount == 0);
    AQBrokerTestUseSyntheticOwnerSignature = NO;
}

static void TestBrokerFrameParserUsesProtocolBound(void) {
    NSUInteger frameLimit = AQBrokerMaximumSessionLineBytes - 1;
    NSString *prefix = @"{\"payload\":\"";
    NSString *suffix = @"\"}";
    NSUInteger prefixBytes = [prefix lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger suffixBytes = [suffix lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;

    NSString *aboveDefaultPayload = [@"" stringByPaddingToLength:65537
        withString:@"x" startingAtIndex:0];
    NSData *aboveDefault = [[NSString stringWithFormat:@"%@%@%@", prefix,
        aboveDefaultPayload, suffix] dataUsingEncoding:NSUTF8StringEncoding];
    BROKER_CHECK(aboveDefault.length > 65536);
    BROKER_CHECK([AQParseJSONWithMaximumBytes(aboveDefault, frameLimit, &error)
        isKindOfClass:NSDictionary.class]);
    BROKER_CHECK(error == nil);

    NSUInteger maximumPayloadBytes = frameLimit - prefixBytes - suffixBytes;
    NSString *maximumPayload = [@"" stringByPaddingToLength:maximumPayloadBytes
        withString:@"x" startingAtIndex:0];
    NSData *maximumFrame = [[NSString stringWithFormat:@"%@%@%@", prefix,
        maximumPayload, suffix] dataUsingEncoding:NSUTF8StringEncoding];
    BROKER_CHECK(maximumFrame.length == frameLimit);
    BROKER_CHECK([AQParseJSONWithMaximumBytes(maximumFrame, frameLimit, &error)
        isKindOfClass:NSDictionary.class]);
    BROKER_CHECK(error == nil);

    NSMutableData *oversizedFrame = [maximumFrame mutableCopy];
    [oversizedFrame appendBytes:" " length:1];
    BROKER_CHECK(AQParseJSONWithMaximumBytes(oversizedFrame, frameLimit, &error) == nil);
    BROKER_CHECK(error.code == AQLimitExceeded);
}

static void TestBrokerReadSessionLineEnforcesLineBound(void) {
    NSMutableData *maximumLine = [NSMutableData dataWithLength:
        AQBrokerMaximumSessionLineBytes - 1U];
    [maximumLine appendBytes:"\n" length:1];
    NSData *line = nil;
    BOOL reachedEOF = NO;
    NSError *error = nil;
    BROKER_CHECK(AQBrokerReadSessionLine(maximumLine, &line, &reachedEOF, &error));
    BROKER_CHECK(line.length == AQBrokerMaximumSessionLineBytes - 1U);
    BROKER_CHECK(error == nil);

    NSMutableData *oversizedLine = [NSMutableData dataWithLength:
        AQBrokerMaximumSessionLineBytes];
    [oversizedLine appendBytes:"\n" length:1];
    line = nil;
    reachedEOF = NO;
    error = nil;
    BROKER_CHECK(!AQBrokerReadSessionLine(oversizedLine, &line, &reachedEOF, &error));
    BROKER_CHECK(line == nil);
    BROKER_CHECK(!reachedEOF);
    BROKER_CHECK(error.code == AQBrokerInvalidRequest);
}

int AQRunBrokerTests(void) {
    @autoreleasepool {
        brokerFailures = 0;
        TestExportVerifier();
        TestPrivateInputFilesRejectSharedPermissions();
        TestPrivateInputFifoRejectedWithoutBlocking();
        TestDeliveredChunksRemainOwnedAcrossReuse();
        TestNoCopyStorageReuseCorruptsRetainedData();
        TestSinkFailurePreventsCompletion();
        TestCompleteWriteHelper();
    TestBrokerFrameParserUsesProtocolBound();
        TestBrokerReadSessionLineEnforcesLineBound();
        TestCanonicalHeaderRequired();
        TestNilSinkRejectedAfterValidFrame();
        TestExportDeliveryWaitsForVerification();
        TestExportVerificationFailuresNeverDeliverBytes();
        TestWrongExportBindingRejected();
        TestTrailingBytesRejectedWithoutDelivery();
        TestSpoolMetadataRejectsMutation();
    TestSpoolIsolationUnavailableFailsBeforeDelivery();
        TestSpoolMutationBeforeDeliveryCannotProduceReceipt();
        TestSpoolMutationDuringDeliveryCannotProduceReceipt();
        TestSpoolPathReplacementCannotAffectVerifiedBytes();
        TestSpoolDiscardRetainsForeignReplacement();
        TestSpoolCapacityReserveBoundary();
    TestSequentialSessionOrdering();
    TestReconnectBlocksMutationAndAllowsInspection();
    TestDeadlineAndLateReply();
        TestReconnectGuard();
        TestXPCEnvelopeRelaysExactAuthorization();
        TestXPCEnvelopeRejectsAuthorizationWithoutBytes();
        TestReconnectPreservesImmutableDeadline();
        TestDeadlineBoundedWrite();
        TestDeadlineIsRecheckedImmediatelyBeforeWrite();
        TestDeadlineWriteRestoresDescriptorFlagsOnFailure();
        TestDurableReceiptFailureIsUncertain();
        TestReceiptQueryUsesFreshDeadlineAfterOperationExpiry();
        TestReceiptQueryRejectsExpiredAndUnboundedQueryDeadlines();
        TestMismatchedReceiptUsesStableErrorWithStaleErrno();
        TestReceiptDeadlineFailureCanRetryWithoutAcknowledgement();
        TestManifestMustMatchSignedDigest();
        TestReplyRaceClosesExportDescriptor();
        TestMutationOutputFailureRetainsUncertainty();
        TestMutationWriteFailureRetainsUncertainty();
        TestMutationClosedPipeRetainsUncertainty();
        TestSourcePathsMustBeBoundedStrings();
        TestSelfCheckReadyWriteFailureReturnsNonzero();
    TestSelfCheckReportsNotReadyUntilXPCProof();
        TestBrokerProcessSurvivesClosedStdoutPipe();
        TestOwnerExportPrepareJournalDispatchOrder();
        TestInvalidWorkflowDoesNotPromptForConsentSignature();
        TestOwnerExportPreparationRequiresOwnerAuthority();
        TestInvalidAdmissionDocumentsDoNotPromptForConsentSignature();
        fprintf(stderr, "broker tests: %d failure(s)\n", brokerFailures);
        return brokerFailures;
    }
}

#ifdef AQ_BROKER_TEST_MAIN
int main(void) { return AQRunBrokerTests() == 0 ? 0 : 1; }
#endif
