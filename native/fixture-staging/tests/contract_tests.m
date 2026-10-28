#import "../core/AQContract.h"
#import <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static int failures;
static int checks;

static void Check(BOOL value, NSString *label) {
    checks++;
    if (!value) {
        failures++;
        fprintf(stderr, "FAIL contract: %s\n", label.UTF8String);
    }
}

static NSData *Bytes(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData *Canonical(id value) {
    return AQCanonicalJSON(value, NULL);
}

static id DeepMutableCopy(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *copy = [NSMutableDictionary dictionary];
        for (id key in value) copy[key] = DeepMutableCopy(value[key]);
        return copy;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *copy = [NSMutableArray array];
        for (id item in value) [copy addObject:DeepMutableCopy(item)];
        return copy;
    }
    return value;
}

static NSString *ErrorName(AQContractErrorCode code) {
    NSArray<NSString *> *names = @[@"INPUT_INVALID", @"LIMIT_EXCEEDED", @"SCHEMA_UNSUPPORTED",
        @"PIN_MISMATCH", @"MISSING_REFERENCE", @"REFERENCE_CYCLE", @"EVIDENCE_CONFLICT",
        @"UNUSED_RECORD"];
    return code >= AQInputInvalid && code <= AQUnusedRecord ? names[code - 1] : @"INPUT_INVALID";
}

static void RejectJSON(NSData *data, AQContractErrorCode code, NSString *label) {
    NSError *error = nil;
    id value = AQParseJSON(data, &error);
    Check(value == nil && [error.domain isEqualToString:AQContractErrorDomain] &&
          error.code == code && [error.localizedDescription isEqualToString:ErrorName(code)], label);
}

static NSMutableDictionary *Pin(NSDictionary *record, NSString *kind) {
    NSString *domain = [kind isEqualToString:@"oracle"] ? @"argus.fixture-oracle.v1"
                                                        : @"argus.fixture-evidence.v1";
    NSString *referenceField = [kind stringByAppendingString:@"_ref"];
    return [@{
        @"schema_version": @1,
        referenceField: (id)record[referenceField],
        @"revision": (id)record[@"revision"],
        @"sha256": (NSString *)AQDigest(domain, record, NULL),
    } mutableCopy];
}

static NSMutableDictionary *BasicFixture(void) {
    return [@{
        @"fixture_id": @"tiny-disc",
        @"platform": @"test",
        @"representation": @"raw",
        @"identity": @"Synthetic test identity",
        @"group_id": @"demo-set",
        @"order": @0,
        @"entrypoint": @"disc.bin",
        @"files": @[@{
            @"path": @"disc.bin", @"role": @"rom", @"size": @1,
            @"sha256": [@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0],
        }],
        @"companions": @[],
        @"facts": @{@"edition": @"test", @"region": @"test", @"disc_set": @"demo-set"},
    } mutableCopy];
}

static NSMutableDictionary *ContractBundle(BOOL genuine) {
    NSString *rule = [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0];
    NSMutableDictionary *fixture = BasicFixture();
    NSMutableDictionary *evidence = [@{
        @"schema_version": @1,
        @"evidence_ref": @"evidence-a",
        @"revision": @"r1",
        @"fixture": DeepMutableCopy(fixture),
        @"corpus_origin": genuine ? @"owner_private_genuine" : @"synthetic",
        @"acceptance_rule_sha256": rule,
        @"method": genuine ? @"independent_reference" : @"synthetic_expectation",
        @"provenance": @"Fabricated unit-test declaration; never qualification evidence.",
        @"limitations": @[@"No real source authenticated."],
        @"conflicts": @[],
        @"evidence_refs": @[],
    } mutableCopy];
    if (genuine) {
        evidence[@"reference"] = [@{
            @"ref": @"source-a", @"revision": @"source-r1",
            @"sha256": [@"e" stringByPaddingToLength:64 withString:@"e" startingAtIndex:0],
        } mutableCopy];
    }
    NSDictionary *evidencePin = Pin(evidence, @"evidence");
    NSMutableDictionary *oracle = [@{
        @"schema_version": @1,
        @"oracle_ref": @"oracle-a",
        @"revision": @"r1",
        @"fixture": DeepMutableCopy(fixture),
        @"corpus_origin": genuine ? @"owner_private_genuine" : @"synthetic",
        @"acceptance_rule_sha256": rule,
        @"method": genuine ? @"independent_reference" : @"synthetic_expectation",
        @"provenance": @"Fabricated unit-test declaration; never qualification evidence.",
        @"limitations": @[@"No real source authenticated."],
        @"conflicts": @[],
        @"evidence_refs": @[evidencePin],
    } mutableCopy];
    NSDictionary *oraclePin = Pin(oracle, @"oracle");
    NSMutableDictionary *manifestFixture = DeepMutableCopy(fixture);
    manifestFixture[@"identity_evidence"] = genuine ? @"independent_reference_pinned_v1"
                                                      : @"synthetic_expectation_v2";
    manifestFixture[@"oracle_pin"] = oraclePin;
    NSMutableDictionary *manifest = [@{
        @"schema_version": @2,
        @"source_authority": @"service_protected_snapshot_v1",
        @"plan_sha256": [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0],
        @"rules_sha256": rule,
        @"coverage_mode": @"mandatory_full_plan",
        @"selected_fixture_ids": @[@"tiny-disc"],
        @"fixtures": @[manifestFixture],
    } mutableCopy];
    return [@{
        @"manifest": manifest,
        @"oracle": oracle,
        @"evidence": [@[evidence] mutableCopy],
        @"authorized_manifest_sha256": (NSString *)AQDigest(@"", manifest, NULL),
        @"authorized_plan_sha256": (id)manifest[@"plan_sha256"],
        @"authorized_rules_sha256": (id)manifest[@"rules_sha256"],
    } mutableCopy];
}

static void RefreshManifestAuthorization(NSMutableDictionary *bundle) {
    NSDictionary *manifest = bundle[@"manifest"];
    bundle[@"authorized_manifest_sha256"] = AQDigest(@"", manifest, NULL);
    bundle[@"authorized_plan_sha256"] = manifest[@"plan_sha256"];
    bundle[@"authorized_rules_sha256"] = manifest[@"rules_sha256"];
}

/** Recompute pins for the flat one-oracle test fixtures used by this harness. */
static void RefreshFlatPins(NSMutableDictionary *bundle) {
    NSMutableDictionary *oracle = bundle[@"oracle"];
    NSArray *evidenceRecords = bundle[@"evidence"];
    for (NSMutableDictionary *pin in oracle[@"evidence_refs"]) {
        for (NSDictionary *record in evidenceRecords) {
            if (![record[@"evidence_ref"] isEqual:pin[@"evidence_ref"]]) continue;
            pin[@"revision"] = record[@"revision"];
            pin[@"sha256"] = AQDigest(@"argus.fixture-evidence.v1", record, NULL);
            break;
        }
    }
    NSDictionary *oracleDigest = Pin(oracle, @"oracle");
    for (NSMutableDictionary *fixture in bundle[@"manifest"][@"fixtures"]) {
        if (![fixture[@"oracle_pin"][@"oracle_ref"] isEqual:oracle[@"oracle_ref"]]) continue;
        fixture[@"oracle_pin"] = DeepMutableCopy(oracleDigest);
    }
    RefreshManifestAuthorization(bundle);
}

static NSArray<NSData *> *EncodedRecords(NSArray *records) {
    NSMutableArray<NSData *> *encoded = [NSMutableArray array];
    for (id record in records) [encoded addObject:Canonical(record)];
    return encoded;
}

static NSDictionary *ValidateBundle(NSDictionary *bundle, NSError **error) {
    return AQValidateSnapshotContract(Canonical(bundle[@"manifest"]),
        @[Canonical(bundle[@"oracle"])], EncodedRecords(bundle[@"evidence"]),
        (NSString *)bundle[@"authorized_manifest_sha256"],
        (NSString *)bundle[@"authorized_plan_sha256"],
        (NSString *)bundle[@"authorized_rules_sha256"], error);
}

static void ExpectContractError(NSDictionary *bundle, AQContractErrorCode code, NSString *label) {
    NSError *error = nil;
    NSDictionary *result = ValidateBundle(bundle, &error);
    Check(result == nil && [error.domain isEqualToString:AQContractErrorDomain] && error.code == code &&
          [error.localizedDescription isEqualToString:ErrorName(code)], label);
}

static void JSONBoundaries(void) {
    for (NSString *text in @[@"", @"null", @"true", @"1", @"{\"x\":+1}", @"{\"x\":01}",
        @"{\"x\":-01}", @"{\"x\":NaN}", @"{\"x\":Infinity}", @"{\"x\":1,}",
        @"{\"x\":[1,]}", @"{\"x\":1}{}", @"{\"x\":\"\\x20\"}", @"{\"x\":\"\\u12\"}",
        @"{\"x\":\"\\udc00\"}", @"{\"x\":\"\\ud800\\u0041\"}",
        @"{\"x\":\"\\ud800\\ud800\"}", @"{\"x\":\"\\ud800x\"}",
        @"{\"x\":\"\n\"}", @"{\"a\":1,\"\\u0061\":2}", @"\ufeff{}",
        @"{\"\\u00e9\":1}", @"{\"x\":\"e\\u0301\"}", @"{\"x\":tru}"]) {
        RejectJSON(Bytes(text), AQInputInvalid, @"strict JSON rejection");
    }

    const uint8_t malformed[][4] = {{0xc0,0xaf,0,0},{0xed,0xa0,0x80,0},
        {0xf4,0x90,0x80,0x80},{0x80,0,0,0},{0xe2,0x82,0,0}};
    const NSUInteger lengths[] = {2,3,4,1,2};
    for (NSUInteger i = 0; i < 5; i++) {
        NSMutableData *data = [Bytes(@"{\"x\":\"") mutableCopy];
        [data appendBytes:malformed[i] length:lengths[i]];
        [data appendData:Bytes(@"\"}")];
        RejectJSON(data, AQInputInvalid, @"invalid UTF-8 is never replaced");
    }

    id pair = AQParseJSON(Bytes(@"{\"\\u006e\\u0061\\u006d\\u0065\":\"Caf\\u00e9\"}"), NULL);
    NSData *pairBytes = AQCanonicalJSON(pair, NULL);
    Check([pairBytes isEqual:Bytes(@"{\"name\":\"Café\"}")],
          @"escaped ASCII keys and Unicode values canonicalize to UTF-8");

    NSDictionary *numbers = AQParseJSON(Bytes(@"{\"lo\":-9223372036854775808,\"hi\":9223372036854775807,\"b\":true,\"i\":1}"), NULL);
    Check([numbers[@"lo"] longLongValue] == LLONG_MIN && [numbers[@"hi"] longLongValue] == LLONG_MAX &&
          CFGetTypeID((__bridge CFTypeRef)numbers[@"b"]) == CFBooleanGetTypeID() &&
          CFGetTypeID((__bridge CFTypeRef)numbers[@"i"]) != CFBooleanGetTypeID(),
          @"signed 64-bit integers and booleans remain distinct");

    for (id value in @[@1.0, @(-0.0), @(ULLONG_MAX), @"e\u0301", @{@"é":@1}, [NSSet set]]) {
        NSError *error = nil;
        Check(AQCanonicalJSON(value, &error) == nil && error.code == AQInputInvalid,
              @"encoder rejects unsupported or lossy values");
    }
    Check([AQCanonicalJSON(@[@YES, @NO, @0, [NSNull null]], NULL) isEqual:Bytes(@"[true,false,0,null]")],
          @"generic encoder accepts JSON values");
    Check([AQCanonicalJSON(@"\b\t\n\f\r\x01/\\\"", NULL) isEqual:Bytes(@"\"\\b\\t\\n\\f\\r\\u0001/\\\\\\\"\"")],
          @"Python control and slash escaping");
    NSError *domainError = nil;
    Check(AQDigest(@"é", @{}, &domainError) == nil && domainError.code == AQInputInvalid,
          @"digest domain must be ASCII");

    NSString *text = [@"x" stringByPaddingToLength:65528 withString:@"x" startingAtIndex:0];
    NSData *limit = Bytes([NSString stringWithFormat:@"{\"x\":\"%@\"}", text]);
    id parsedLimit = AQParseJSON(limit, NULL);
    NSData *canonicalLimit = AQCanonicalJSON(parsedLimit, NULL);
    Check(limit.length == 65536 && parsedLimit != nil && canonicalLimit.length == 65536,
          @"64 KiB input and canonical byte buffers establish the documented 128 KiB ceiling");
    NSMutableData *oversized = [limit mutableCopy];
    [oversized appendData:Bytes(@" ")];
    RejectJSON(oversized, AQLimitExceeded, @"raw byte limit enforced before parsing");

    NSMutableString *deep = [@"{\"x\":" mutableCopy];
    for (NSUInteger i = 0; i < 31; i++) [deep appendString:@"["];
    [deep appendString:@"0"];
    for (NSUInteger i = 0; i < 31; i++) [deep appendString:@"]"];
    [deep appendString:@"}"];
    Check(AQParseJSON(Bytes(deep), NULL) != nil, @"root-zero depth 32 accepted");
    [deep replaceOccurrencesOfString:@"0" withString:@"[0]" options:0 range:NSMakeRange(0, deep.length)];
    RejectJSON(Bytes(deep), AQLimitExceeded, @"depth 33 rejected");
}

static void ContractBoundaries(void) {
    NSMutableDictionary *bundle = ContractBundle(NO);
    NSError *error = nil;
    NSDictionary *result = ValidateBundle(bundle, &error);
    Check(result != nil && error == nil, @"synthetic contract passes");
    NSDictionary *assessment = [result[@"fixtures"] firstObject];
    Check([assessment[@"independent_support"] isEqual:@"synthetic_only"] &&
          [assessment[@"byte_integrity"] isEqual:@"not_checked"] &&
          [assessment[@"structural_expectation"] isEqual:@"validated"] &&
          [assessment[@"owner_approval"] isEqual:@"not_checked"],
          @"assessment separates declaration, bytes, and owner approval");

    bundle = ContractBundle(YES);
    result = ValidateBundle(bundle, &error);
    Check(result != nil && [[result[@"fixtures"] firstObject][@"independent_support"]
          isEqual:@"pinned_unverified"],
          @"caller-controlled document input cannot elevate genuine evidence");

    for (NSString *key in @[@"authorized_manifest_sha256", @"authorized_plan_sha256",
                            @"authorized_rules_sha256"]) {
        NSMutableDictionary *mutated = DeepMutableCopy(bundle);
        mutated[key] = [@"0" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0];
        ExpectContractError(mutated, AQPinMismatch, @"authorization pin mismatch is rejected");
        Check(![mutated[key] containsString:@"private"], @"pin failure leaks no caller data");
    }

    NSMutableDictionary *mutated = DeepMutableCopy(bundle);
    mutated[@"manifest"][@"fixtures"][0][@"oracle_pin"][@"oracle_ref"] = @"absent";
    RefreshManifestAuthorization(mutated);
    ExpectContractError(mutated, AQMissingReference, @"missing oracle is rejected");

    mutated = DeepMutableCopy(bundle);
    mutated[@"evidence"] = [@[] mutableCopy];
    ExpectContractError(mutated, AQMissingReference, @"missing evidence is rejected");

    mutated = DeepMutableCopy(bundle);
    mutated[@"oracle"][@"revision"] = @"r2";
    ExpectContractError(mutated, AQPinMismatch, @"changed oracle revision is rejected");
    mutated = DeepMutableCopy(bundle);
    mutated[@"oracle"][@"provenance"] = @"Changed declaration.";
    ExpectContractError(mutated, AQPinMismatch, @"changed oracle bytes are rejected");
    mutated = DeepMutableCopy(bundle);
    mutated[@"evidence"][0][@"revision"] = @"r2";
    ExpectContractError(mutated, AQPinMismatch, @"changed evidence revision is rejected");

    mutated = DeepMutableCopy(bundle);
    mutated[@"oracle"][@"fixture"][@"identity"] = @"Different identity";
    RefreshFlatPins(mutated);
    ExpectContractError(mutated, AQEvidenceConflict, @"manifest-oracle binding is exact");
    mutated = DeepMutableCopy(bundle);
    mutated[@"oracle"][@"acceptance_rule_sha256"] =
        [@"d" stringByPaddingToLength:64 withString:@"d" startingAtIndex:0];
    RefreshFlatPins(mutated);
    ExpectContractError(mutated, AQEvidenceConflict, @"acceptance rule must match manifest");
    mutated = DeepMutableCopy(bundle);
    mutated[@"manifest"][@"fixtures"][0][@"identity_evidence"] = @"synthetic_expectation_v2";
    RefreshManifestAuthorization(mutated);
    ExpectContractError(mutated, AQEvidenceConflict, @"genuine label cannot claim synthetic tier");

    mutated = DeepMutableCopy(bundle);
    mutated[@"oracle"][@"conflicts"] = @[@"identity disagreement"];
    ExpectContractError(mutated, AQEvidenceConflict, @"oracle conflicts fail closed");
    mutated = DeepMutableCopy(bundle);
    mutated[@"evidence"][0][@"conflicts"] = @[@"identity disagreement"];
    ExpectContractError(mutated, AQEvidenceConflict, @"evidence conflicts fail closed");

    mutated = DeepMutableCopy(bundle);
    NSMutableDictionary *selfCycle = mutated[@"evidence"][0];
    selfCycle[@"evidence_refs"] = @[Pin(selfCycle, @"evidence")];
    ExpectContractError(mutated, AQReferenceCycle, @"self-referential evidence is rejected");

    mutated = DeepMutableCopy(bundle);
    NSMutableDictionary *first = mutated[@"evidence"][0];
    NSMutableDictionary *second = DeepMutableCopy(first);
    second[@"evidence_ref"] = @"evidence-b";
    first[@"evidence_refs"] = @[Pin(second, @"evidence")];
    second[@"evidence_refs"] = @[Pin(first, @"evidence")];
    [mutated[@"evidence"] addObject:second];
    ExpectContractError(mutated, AQReferenceCycle, @"two-node evidence cycle is rejected");

    mutated = ContractBundle(YES);
    first = mutated[@"evidence"][0];
    second = DeepMutableCopy(first);
    second[@"evidence_ref"] = @"evidence-b";
    second[@"reference"][@"sha256"] =
        [@"d" stringByPaddingToLength:64 withString:@"d" startingAtIndex:0];
    [mutated[@"evidence"] addObject:second];
    mutated[@"oracle"][@"evidence_refs"] = @[Pin(first, @"evidence"), Pin(second, @"evidence")];
    RefreshFlatPins(mutated);
    ExpectContractError(mutated, AQEvidenceConflict,
                        @"shared external references must agree on revision and digest");

    mutated = ContractBundle(YES);
    first = mutated[@"evidence"][0];
    second = DeepMutableCopy(first);
    second[@"evidence_ref"] = @"evidence-b";
    [mutated[@"evidence"] addObject:second];
    mutated[@"oracle"][@"evidence_refs"] = @[Pin(first, @"evidence"), Pin(second, @"evidence")];
    RefreshFlatPins(mutated);
    result = ValidateBundle(mutated, &error);
    Check(result != nil && [[result[@"fixtures"] firstObject][@"independent_support"]
          isEqual:@"pinned_unverified"],
          @"every reachable genuine record remains pinned without native authority");

    mutated = DeepMutableCopy(bundle);
    NSMutableDictionary *unused = DeepMutableCopy(mutated[@"evidence"][0]);
    unused[@"evidence_ref"] = @"unused-evidence";
    [mutated[@"evidence"] addObject:unused];
    ExpectContractError(mutated, AQUnusedRecord, @"unreachable evidence is rejected");
    mutated = DeepMutableCopy(bundle);
    [mutated[@"evidence"] addObject:DeepMutableCopy(mutated[@"evidence"][0])];
    ExpectContractError(mutated, AQInputInvalid, @"duplicate evidence identifiers are rejected");

    NSMutableArray<NSData *> *tooMany = [NSMutableArray array];
    for (NSUInteger i = 0; i < 129; i++) [tooMany addObject:Canonical(bundle[@"oracle"])];
    error = nil;
    NSDictionary *limited = AQValidateSnapshotContract(Canonical(bundle[@"manifest"]), tooMany, @[],
        (NSString *)bundle[@"authorized_manifest_sha256"],
        (NSString *)bundle[@"authorized_plan_sha256"],
        (NSString *)bundle[@"authorized_rules_sha256"], &error);
    Check(limited == nil && error.code == AQLimitExceeded &&
          [error.localizedDescription isEqual:@"LIMIT_EXCEEDED"], @"graph record limit is enforced");

    for (NSString *location in @[@"manifest", @"fixture", @"oracle", @"evidence", @"reference",
                                @"facts", @"file", @"pin"]) {
        mutated = DeepMutableCopy(bundle);
        NSMutableDictionary *target = nil;
        if ([location isEqual:@"manifest"]) target = mutated[@"manifest"];
        else if ([location isEqual:@"fixture"]) target = mutated[@"manifest"][@"fixtures"][0];
        else if ([location isEqual:@"oracle"]) target = mutated[@"oracle"];
        else if ([location isEqual:@"evidence"]) target = mutated[@"evidence"][0];
        else if ([location isEqual:@"reference"]) target = mutated[@"evidence"][0][@"reference"];
        else if ([location isEqual:@"facts"]) target = mutated[@"evidence"][0][@"fixture"][@"facts"];
        else if ([location isEqual:@"file"]) target = mutated[@"evidence"][0][@"fixture"][@"files"][0];
        else if ([location isEqual:@"pin"]) target = mutated[@"manifest"][@"fixtures"][0][@"oracle_pin"];
        target[@"manifest_sha256"] = [@"9" stringByPaddingToLength:64 withString:@"9" startingAtIndex:0];
        ExpectContractError(mutated, AQInputInvalid, @"unknown back-reference fields are rejected");
    }

    for (NSString *location in @[@"manifest", @"oracle", @"evidence"]) {
        mutated = DeepMutableCopy(bundle);
        if ([location isEqual:@"manifest"]) mutated[@"manifest"][@"schema_version"] = @1;
        else if ([location isEqual:@"oracle"]) mutated[@"oracle"][@"schema_version"] = @2;
        else mutated[@"evidence"][0][@"schema_version"] = @2;
        ExpectContractError(mutated, AQSchemaUnsupported, @"legacy schema versions are rejected");
    }

    mutated = DeepMutableCopy(bundle);
    [mutated[@"manifest"][@"fixtures"][0] removeObjectForKey:@"facts"];
    [mutated[@"oracle"][@"fixture"] removeObjectForKey:@"facts"];
    [mutated[@"evidence"][0][@"fixture"] removeObjectForKey:@"facts"];
    RefreshFlatPins(mutated);
    result = ValidateBundle(mutated, &error);
    Check(result != nil, @"facts are optional when absent from every binding");
}

static void FixtureGraphBoundaries(void) {
    NSMutableDictionary *bundle = ContractBundle(NO);
    NSMutableDictionary *fixture = bundle[@"manifest"][@"fixtures"][0];
    NSMutableDictionary *oracleFixture = bundle[@"oracle"][@"fixture"];
    NSMutableDictionary *evidenceFixture = bundle[@"evidence"][0][@"fixture"];
    NSMutableDictionary *track = [@{
        @"path": @"track.bin", @"role": @"track", @"size": @1,
        @"sha256": [@"d" stringByPaddingToLength:64 withString:@"d" startingAtIndex:0],
    } mutableCopy];
    [fixture[@"files"] addObject:DeepMutableCopy(track)];
    [oracleFixture[@"files"] addObject:track];
    [evidenceFixture[@"files"] addObject:DeepMutableCopy(track)];
    fixture[@"companions"] = [@[@{@"source": @"disc.bin", @"target": @"track.bin"}] mutableCopy];
    oracleFixture[@"companions"] = DeepMutableCopy(fixture[@"companions"]);
    evidenceFixture[@"companions"] = DeepMutableCopy(fixture[@"companions"]);
    RefreshFlatPins(bundle);
    NSError *error = nil;
    Check(ValidateBundle(bundle, &error) != nil, @"complete companion graph passes");

    NSMutableDictionary *mutated = DeepMutableCopy(bundle);
    [mutated[@"evidence"][0][@"fixture"][@"files"] exchangeObjectAtIndex:0
        withObjectAtIndex:1];
    RefreshFlatPins(mutated);
    ExpectContractError(mutated, AQEvidenceConflict, @"evidence array ordering is bound exactly");

    for (NSString *path in @[@"/disc.bin", @"../disc.bin", @"a//b", @"a/./b",
                             @"disc.bin/child", @"DISC.bin"]) {
        mutated = ContractBundle(NO);
        fixture = mutated[@"manifest"][@"fixtures"][0];
        NSMutableDictionary *file = [fixture[@"files"][0] mutableCopy];
        file[@"path"] = path;
        if ([path isEqual:@"disc.bin/child"] || [path isEqual:@"DISC.bin"]) [fixture[@"files"] addObject:file];
        else fixture[@"files"] = [@[file] mutableCopy];
        fixture[@"entrypoint"] = path;
        ExpectContractError(mutated, AQInputInvalid, @"unsafe or colliding paths are rejected");
    }

    mutated = ContractBundle(NO);
    NSMutableDictionary *badSize = [mutated[@"manifest"][@"fixtures"][0][@"files"][0] mutableCopy];
    badSize[@"size"] = @-1;
    mutated[@"manifest"][@"fixtures"][0][@"files"] = [@[badSize] mutableCopy];
    ExpectContractError(mutated, AQInputInvalid, @"negative file sizes are rejected");

    mutated = ContractBundle(NO);
    track = [@{
        @"path": @"track.bin", @"role": @"track", @"size": @1,
        @"sha256": [@"d" stringByPaddingToLength:64 withString:@"d" startingAtIndex:0],
    } mutableCopy];
    [mutated[@"manifest"][@"fixtures"][0][@"files"] addObject:track];
    ExpectContractError(mutated, AQInputInvalid, @"unreachable companion files are rejected");
}

static void ContractMutationBoundaries(void) {
    NSMutableDictionary *mutated = ContractBundle(NO);
    NSMutableDictionary *manifestFixture = mutated[@"manifest"][@"fixtures"][0];
    NSMutableDictionary *oracleFixture = mutated[@"oracle"][@"fixture"];
    NSMutableDictionary *evidenceFixture = mutated[@"evidence"][0][@"fixture"];
    NSMutableDictionary *alias = [DeepMutableCopy(manifestFixture[@"files"][0]) mutableCopy];
    alias[@"path"] = @"DISC.bin";
    alias[@"role"] = @"track";
    for (NSMutableDictionary *fixture in @[manifestFixture, oracleFixture, evidenceFixture]) {
        [fixture[@"files"] addObject:DeepMutableCopy(alias)];
        fixture[@"companions"] = [@[@{@"source": @"disc.bin", @"target": @"DISC.bin"}] mutableCopy];
    }
    RefreshFlatPins(mutated);
    ExpectContractError(mutated, AQInputInvalid,
                        @"case-folded path aliases are rejected after all other pins agree");

    mutated = ContractBundle(NO);
    mutated[@"manifest"][@"fixtures"][0][@"identity"] = @"Manifest-only identity";
    RefreshManifestAuthorization(mutated);
    ExpectContractError(mutated, AQEvidenceConflict,
                        @"manifest fixture identity is bound to its oracle fixture");
}

/** Public parent-harness entry point; reads synthetic golden data only. */
int AQRunContractTests(NSString *fixtureDirectory) {
    failures = 0;
    checks = 0;
    NSError *error = nil;
    NSData *raw = [NSData dataWithContentsOfFile:
        [fixtureDirectory stringByAppendingPathComponent:@"oracle-contract-v1-golden.json"]];
    // Foundation loads only the test envelope; candidate documents use AQJSON.
    NSDictionary *golden = raw ? [NSJSONSerialization JSONObjectWithData:raw options:0 error:&error] : nil;
    Check(golden != nil, @"golden envelope is available");
    if (!golden) return failures;

    for (NSDictionary *vector in golden[@"canonical_vectors"]) {
        id value = AQParseJSON(Bytes(vector[@"input_json"]), NULL);
        Check([AQCanonicalJSON(value, NULL) isEqual:Bytes(vector[@"canonical_utf8"])],
              @"golden canonical bytes");
        Check([AQDigest(@"", value, NULL) isEqual:vector[@"manifest_sha256"]], @"golden manifest SHA-256");
        Check([AQDigest(@"argus.fixture-oracle.v1", value, NULL) isEqual:vector[@"oracle_sha256"]],
              @"golden oracle SHA-256");
        Check([AQDigest(@"argus.fixture-evidence.v1", value, NULL) isEqual:vector[@"evidence_sha256"]],
              @"golden evidence SHA-256");
    }
    for (NSDictionary *vector in golden[@"invalid_json_vectors"]) {
        error = nil;
        id value = AQParseJSON(Bytes(vector[@"input_json"]), &error);
        Check([vector[@"parse_only_valid"] boolValue] ? value != nil : value == nil && error != nil,
              vector[@"id"]);
    }
    if (AQParseJSON(Bytes(@"{}"), NULL)) JSONBoundaries();

    NSDictionary *snapshot = golden[@"snapshot_vector"];
    NSMutableArray *oracles = [NSMutableArray array], *evidenceRecords = [NSMutableArray array];
    for (NSString *text in snapshot[@"oracle_canonical_utf8"]) [oracles addObject:Bytes(text)];
    for (NSString *text in snapshot[@"evidence_canonical_utf8"]) [evidenceRecords addObject:Bytes(text)];
    error = nil;
    NSDictionary *result = AQValidateSnapshotContract(Bytes(snapshot[@"manifest_canonical_utf8"]),
        oracles, evidenceRecords, (NSString *)snapshot[@"authorized_manifest_sha256"],
        (NSString *)snapshot[@"authorized_plan_sha256"],
        (NSString *)snapshot[@"authorized_rules_sha256"], &error);
    Check(result != nil && error == nil, @"golden snapshot graph passes");
    Check([result[@"manifest_sha256"] isEqual:snapshot[@"authorized_manifest_sha256"]],
          @"golden manifest pin stays exact");
    Check([[result[@"fixtures"] firstObject][@"independent_support"]
          isEqual:snapshot[@"expected_independent_support"]], @"golden support tier");

    ContractBoundaries();
    FixtureGraphBoundaries();
    ContractMutationBoundaries();
    fprintf(stderr, "contract tests: %d checks, %d failures\n", checks, failures);
    return failures;
}

#ifdef AQ_CONTRACT_TEST_MAIN
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *fixtures = argc > 1 ? [NSString stringWithUTF8String:argv[1]]
                                     : @"native/fixture-staging/fixtures";
        return AQRunContractTests(fixtures) ? 1 : 0;
    }
}
#endif
