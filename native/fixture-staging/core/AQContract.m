#import "AQContract.h"
#import <CoreFoundation/CoreFoundation.h>
#include <string.h>

static const NSUInteger AQMaximumGraphRecords = 128;
static NSString * const AQSourceAuthority = @"service_protected_snapshot_v1";
static NSString * const AQOracleDomain = @"argus.fixture-oracle.v1";
static NSString * const AQEvidenceDomain = @"argus.fixture-evidence.v1";

static BOOL AQFailContract(NSError **error, AQContractErrorCode code) {
    if (error) *error = AQContractError(code);
    return NO;
}

static BOOL AQIsBoolean(NSNumber *number) {
    return CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID();
}

static BOOL AQIsInteger(NSNumber *number) {
    if (![number isKindOfClass:[NSNumber class]] || AQIsBoolean(number)) return NO;
    const char *type = number.objCType;
    return type && type[0] && strchr("cCsSiIlLqQ", type[0]);
}

static BOOL AQIsPythonWhitespace(unichar character) {
    switch (character) {
        case 0x0009: case 0x000a: case 0x000b: case 0x000c: case 0x000d:
        case 0x001c: case 0x001d: case 0x001e: case 0x001f: case 0x0020:
        case 0x0085: case 0x00a0: case 0x1680: case 0x2028: case 0x2029:
        case 0x202f: case 0x205f: case 0x3000:
            return YES;
        default:
            return character >= 0x2000 && character <= 0x200a;
    }
}

static NSUInteger AQScalarLength(NSString *text) {
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < text.length; i++, count++) {
        unichar character = [text characterAtIndex:i];
        if (character >= 0xd800 && character <= 0xdbff && i + 1 < text.length) i++;
    }
    return count;
}

static BOOL AQHasControl(NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar character = [text characterAtIndex:i];
        if (character <= 0x001f || (character >= 0x007f && character <= 0x009f)) return YES;
    }
    return NO;
}

static NSString *AQText(id value, NSUInteger maximum, NSError **error) {
    if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0 ||
        AQScalarLength(value) > maximum || AQIsPythonWhitespace([value characterAtIndex:0]) ||
        AQIsPythonWhitespace([value characterAtIndex:[(NSString *)value length] - 1]) || AQHasControl(value)) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    return value;
}

static NSString *AQIdentifier(id value, NSError **error) {
    NSString *identifier = AQText(value, 256, error);
    if (!identifier) return nil;
    if ([identifier isEqualToString:@"."] || [identifier isEqualToString:@".."] ||
        [identifier rangeOfString:@"/"].location != NSNotFound ||
        [identifier rangeOfString:@"\\"].location != NSNotFound ||
        [identifier rangeOfString:@":"].location != NSNotFound) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    return identifier;
}

static BOOL AQDigestText(id value) {
    if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 64) return NO;
    NSString *digest = value;
    for (NSUInteger i = 0; i < 64; i++) {
        unichar character = [digest characterAtIndex:i];
        if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'))) {
            return NO;
        }
    }
    return YES;
}

static NSString *AQDigestValue(id value, NSError **error) {
    if (!AQDigestText(value)) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    return value;
}

static NSDictionary *AQObjectFields(id value, NSArray<NSString *> *required,
                                    NSArray<NSString *> *optional, NSError **error) {
    if (![value isKindOfClass:[NSDictionary class]]) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    NSDictionary *object = value;
    NSSet *requiredSet = [NSSet setWithArray:required];
    NSSet *allowedSet = [requiredSet setByAddingObjectsFromArray:optional];
    if (object.count < requiredSet.count || object.count > allowedSet.count) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    for (id key in object) {
        if (![key isKindOfClass:[NSString class]] || ![allowedSet containsObject:key]) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
    }
    for (NSString *key in requiredSet) {
        if (object[key] == nil) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
    }
    return object;
}

static NSArray *AQArrayValue(id value, BOOL nonempty, NSError **error) {
    if (![value isKindOfClass:[NSArray class]] || (nonempty && [(NSArray *)value count] == 0)) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    return value;
}

static BOOL AQNumberVersion(id value, long long expected, NSError **error) {
    if (!AQIsInteger(value) || [(NSNumber *)value longLongValue] != expected) {
        return AQFailContract(error, AQSchemaUnsupported);
    }
    return YES;
}

static BOOL AQNonnegative(id value, NSError **error) {
    if (!AQIsInteger(value) || [(NSNumber *)value longLongValue] < 0) {
        return AQFailContract(error, AQInputInvalid);
    }
    return YES;
}

static NSString *AQFold(NSString *value) {
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *folded = [value stringByFoldingWithOptions:NSCaseInsensitiveSearch locale:locale];
    folded = [folded decomposedStringWithCanonicalMapping];
    return [folded decomposedStringWithCanonicalMapping];
}

static NSString *AQPath(id value, NSError **error) {
    NSString *path = AQText(value, 4096, error);
    if (!path) return nil;
    if ([path rangeOfString:@"\\"].location != NSNotFound ||
        [path rangeOfString:@":"].location != NSNotFound) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    for (NSString *component in [path componentsSeparatedByString:@"/"]) {
        if (component.length == 0 || [component isEqualToString:@"."] ||
            [component isEqualToString:@".."]) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
    }
    return path;
}

static NSDictionary *AQPin(id value, NSString *kind, NSError **error) {
    NSString *referenceField = [kind stringByAppendingString:@"_ref"];
    NSDictionary *pin = AQObjectFields(value, @[@"schema_version", referenceField, @"revision", @"sha256"],
                                       @[], error);
    if (!pin || !AQNumberVersion(pin[@"schema_version"], 1, error) ||
        !AQIdentifier(pin[referenceField], error) || !AQText(pin[@"revision"], 256, error) ||
        !AQDigestValue(pin[@"sha256"], error)) return nil;
    return pin;
}

static NSDictionary *AQParseObject(NSData *data, NSError **error) {
    if (![data isKindOfClass:[NSData class]]) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    id parsed = AQParseJSON(data, error);
    if (!parsed) return nil;
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    return parsed;
}

static NSDictionary *AQFixtureBinding(NSDictionary *fixture) {
    NSArray<NSString *> *keys = @[@"fixture_id", @"platform", @"representation", @"identity",
        @"group_id", @"order", @"entrypoint", @"files", @"companions"];
    NSMutableDictionary *binding = [NSMutableDictionary dictionary];
    for (NSString *key in keys) binding[key] = fixture[key];
    if (fixture[@"facts"] != nil) binding[@"facts"] = fixture[@"facts"];
    return [binding copy];
}

static BOOL AQVisitGraphNode(NSString *node, NSDictionary<NSString *, NSArray<NSString *> *> *adjacency,
                             NSMutableSet<NSString *> *active, NSMutableSet<NSString *> *visited,
                             BOOL provenance, AQContractErrorCode *failure) {
    if ([active containsObject:node]) {
        *failure = provenance ? AQReferenceCycle : AQInputInvalid;
        return NO;
    }
    if ([visited containsObject:node]) return YES;
    NSArray<NSString *> *children = adjacency[node];
    if (children == nil) {
        *failure = provenance ? AQMissingReference : AQInputInvalid;
        return NO;
    }
    [active addObject:node];
    for (NSString *child in children) {
        if (!AQVisitGraphNode(child, adjacency, active, visited, provenance, failure)) return NO;
    }
    [active removeObject:node];
    [visited addObject:node];
    return YES;
}

static NSSet<NSString *> *AQWalkGraph(NSArray<NSString *> *roots,
                                      NSDictionary<NSString *, NSArray<NSString *> *> *adjacency,
                                      BOOL provenance, NSError **error) {
    NSMutableSet<NSString *> *active = [NSMutableSet set];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    AQContractErrorCode failure = AQInputInvalid;
    for (NSString *root in roots) {
        if (!AQVisitGraphNode(root, adjacency, active, visited, provenance, &failure)) {
            AQFailContract(error, failure);
            return nil;
        }
    }
    return [visited copy];
}

static NSDictionary *AQValidatedFixture(id value, BOOL manifest,
                                        NSDictionary **bindingOut, NSDictionary **pinOut,
                                        NSError **error) {
    NSArray<NSString *> *required = @[@"fixture_id", @"platform", @"representation", @"identity",
        @"group_id", @"order", @"entrypoint", @"files", @"companions"];
    NSMutableArray<NSString *> *fixtureRequired = [required mutableCopy];
    if (manifest) [fixtureRequired addObjectsFromArray:@[@"identity_evidence", @"oracle_pin"]];
    NSDictionary *fixture = AQObjectFields(value, fixtureRequired, @[@"facts"], error);
    if (!fixture || !AQIdentifier(fixture[@"fixture_id"], error)) return nil;
    for (NSString *key in @[@"platform", @"representation", @"group_id"]) {
        if (!AQText(fixture[key], 256, error)) return nil;
    }
    if (!AQText(fixture[@"identity"], 512, error) || !AQNonnegative(fixture[@"order"], error)) return nil;
    NSString *entrypoint = AQPath(fixture[@"entrypoint"], error);
    if (!entrypoint) return nil;

    NSArray *files = AQArrayValue(fixture[@"files"], YES, error);
    if (!files) return nil;
    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    NSMutableDictionary<NSArray<NSString *> *, NSArray<NSString *> *> *components =
        [NSMutableDictionary dictionary];
    for (id item in files) {
        NSDictionary *file = AQObjectFields(item, @[@"path", @"role", @"size", @"sha256"], @[], error);
        if (!file) return nil;
        NSString *path = AQPath(file[@"path"], error);
        if (!path || !AQText(file[@"role"], 64, error) ||
            !AQNonnegative(file[@"size"], error) || !AQDigestValue(file[@"sha256"], error)) return nil;
        if ([paths containsObject:path]) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        [paths addObject:path];
        NSMutableArray<NSString *> *spelling = [NSMutableArray array];
        NSMutableArray<NSString *> *folded = [NSMutableArray array];
        for (NSString *component in [path componentsSeparatedByString:@"/"]) {
            [spelling addObject:component];
            [folded addObject:AQFold(component)];
            NSArray<NSString *> *key = [folded copy];
            NSArray<NSString *> *existing = components[key];
            NSArray<NSString *> *current = [spelling copy];
            if (existing != nil && ![existing isEqualToArray:current]) {
                AQFailContract(error, AQInputInvalid);
                return nil;
            }
            components[key] = current;
        }
    }

    for (NSString *path in paths) {
        NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
        for (NSUInteger length = 1; length < parts.count; length++) {
            NSString *prefix = [[parts subarrayWithRange:NSMakeRange(0, length)]
                componentsJoinedByString:@"/"];
            if ([paths containsObject:prefix]) {
                AQFailContract(error, AQInputInvalid);
                return nil;
            }
        }
    }

    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *mutableAdjacency =
        [NSMutableDictionary dictionary];
    for (NSString *path in paths) mutableAdjacency[path] = [NSMutableArray array];
    NSArray *companions = AQArrayValue(fixture[@"companions"], NO, error);
    if (!companions) return nil;
    NSMutableSet<NSArray<NSString *> *> *edges = [NSMutableSet set];
    for (id item in companions) {
        NSDictionary *edge = AQObjectFields(item, @[@"source", @"target"], @[], error);
        if (!edge) return nil;
        NSString *source = AQPath(edge[@"source"], error);
        NSString *target = AQPath(edge[@"target"], error);
        NSArray<NSString *> *edgeKey = @[source ?: @"", target ?: @""];
        if (!source || !target || ![paths containsObject:source] || ![paths containsObject:target] ||
            [edges containsObject:edgeKey]) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        [edges addObject:edgeKey];
        [mutableAdjacency[source] addObject:target];
    }
    NSDictionary *adjacency = [mutableAdjacency copy];
    NSSet *reachable = AQWalkGraph(@[entrypoint], adjacency, NO, error);
    if (!reachable || ![reachable isEqualToSet:paths]) return nil;

    if (fixture[@"facts"] != nil) {
        NSDictionary *facts = AQObjectFields(fixture[@"facts"], @[],
                                              @[@"edition", @"region", @"disc_set"], error);
        if (!facts || facts.count == 0) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        for (id fact in facts.allValues) if (!AQText(fact, 256, error)) return nil;
    }

    if (manifest) {
        NSString *label = AQText(fixture[@"identity_evidence"], 4096, error);
        if (!label || !([label isEqualToString:@"synthetic_expectation_v2"] ||
                        [label isEqualToString:@"independent_reference_pinned_v1"])) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        NSDictionary *pin = AQPin(fixture[@"oracle_pin"], @"oracle", error);
        if (!pin) return nil;
        if (pinOut) *pinOut = pin;
    }
    if (bindingOut) *bindingOut = AQFixtureBinding(fixture);
    return fixture;
}

static NSDictionary *AQRecord(NSData *data, NSString *kind, NSError **error) {
    NSDictionary *document = AQParseObject(data, error);
    if (!document) return nil;
    NSString *referenceField = [kind stringByAppendingString:@"_ref"];
    NSArray<NSString *> *required = @[@"schema_version", referenceField, @"revision", @"fixture",
        @"corpus_origin", @"acceptance_rule_sha256", @"method", @"provenance",
        @"limitations", @"conflicts", @"evidence_refs"];
    NSArray<NSString *> *optional = [kind isEqualToString:@"evidence"] ? @[@"reference"] : @[];
    NSDictionary *record = AQObjectFields(document, required, optional, error);
    if (!record || !AQNumberVersion(record[@"schema_version"], 1, error) ||
        !AQIdentifier(record[referenceField], error) || !AQText(record[@"revision"], 256, error) ||
        !AQValidatedFixture(record[@"fixture"], NO, NULL, NULL, error) ||
        !AQDigestValue(record[@"acceptance_rule_sha256"], error)) return nil;

    NSString *origin = AQText(record[@"corpus_origin"], 4096, error);
    if (!origin) return nil;
    NSString *expectedMethod = nil;
    if ([origin isEqualToString:@"synthetic"]) expectedMethod = @"synthetic_expectation";
    if ([origin isEqualToString:@"owner_private_genuine"]) expectedMethod = @"independent_reference";
    if (expectedMethod == nil || ![record[@"method"] isKindOfClass:[NSString class]] ||
        ![(NSString *)record[@"method"] isEqualToString:expectedMethod] ||
        !AQText(record[@"provenance"], 4096, error)) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }

    for (NSString *key in @[@"limitations", @"conflicts"]) {
        NSArray *values = AQArrayValue(record[key], NO, error);
        if (!values) return nil;
        NSMutableSet<NSString *> *distinct = [NSMutableSet set];
        for (id item in values) {
            NSString *text = AQText(item, 4096, error);
            if (!text || [distinct containsObject:text]) {
                AQFailContract(error, AQInputInvalid);
                return nil;
            }
            [distinct addObject:text];
        }
    }
    if ([(NSArray *)record[@"conflicts"] count] != 0) {
        AQFailContract(error, AQEvidenceConflict);
        return nil;
    }

    NSArray *evidencePins = AQArrayValue(record[@"evidence_refs"], NO, error);
    if (!evidencePins) return nil;
    NSMutableSet<NSString *> *evidenceReferences = [NSMutableSet set];
    for (id item in evidencePins) {
        NSDictionary *pin = AQPin(item, @"evidence", error);
        NSString *evidenceReference = pin[@"evidence_ref"];
        if (!pin || evidenceReference == nil ||
            [evidenceReferences containsObject:evidenceReference]) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        [evidenceReferences addObject:evidenceReference];
    }

    if ([origin isEqualToString:@"owner_private_genuine"]) {
        if ([kind isEqualToString:@"oracle"] && evidenceReferences.count == 0) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        if ([kind isEqualToString:@"evidence"]) {
            NSDictionary *reference = AQObjectFields(record[@"reference"],
                                                      @[@"ref", @"revision", @"sha256"], @[], error);
            if (!reference || !AQText(reference[@"ref"], 4096, error) ||
                !AQText(reference[@"revision"], 256, error) ||
                !AQDigestValue(reference[@"sha256"], error)) return nil;
        }
    } else if (record[@"reference"] != nil) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    return record;
}

static NSDictionary *AQRegistry(NSArray *documents, NSString *kind, NSError **error) {
    NSMutableDictionary<NSString *, NSDictionary *> *records = [NSMutableDictionary dictionary];
    for (id raw in documents) {
        NSDictionary *record = AQRecord(raw, kind, error);
        if (!record) return nil;
        NSString *name = record[[kind stringByAppendingString:@"_ref"]];
        if (records[name] != nil) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        records[name] = record;
    }
    return [records copy];
}

static BOOL AQCheckPin(NSDictionary *pin, NSDictionary *record, NSString *kind, NSError **error) {
    NSString *domain = [kind isEqualToString:@"oracle"] ? AQOracleDomain : AQEvidenceDomain;
    if (![(NSString *)pin[@"revision"] isEqualToString:(NSString *)record[@"revision"]]) {
        return AQFailContract(error, AQPinMismatch);
    }
    NSString *digest = AQDigest(domain, record, error);
    if (!digest) return NO;
    if (![(NSString *)pin[@"sha256"] isEqualToString:digest]) {
        return AQFailContract(error, AQPinMismatch);
    }
    return YES;
}

static BOOL AQJSONEqual(id left, id right) {
    if (left == right) return YES;
    if (left == nil || right == nil) return NO;
    if ([left isKindOfClass:[NSNumber class]] || [right isKindOfClass:[NSNumber class]]) {
        if (![left isKindOfClass:[NSNumber class]] || ![right isKindOfClass:[NSNumber class]]) return NO;
        BOOL leftBoolean = AQIsBoolean(left), rightBoolean = AQIsBoolean(right);
        if (leftBoolean != rightBoolean) return NO;
        return [(NSNumber *)left longLongValue] == [(NSNumber *)right longLongValue];
    }
    if ([left isKindOfClass:[NSString class]] || [right isKindOfClass:[NSString class]]) {
        return [left isKindOfClass:[NSString class]] && [right isKindOfClass:[NSString class]] &&
            [(NSString *)left isEqualToString:right];
    }
    if ([left isKindOfClass:[NSArray class]] || [right isKindOfClass:[NSArray class]]) {
        if (![left isKindOfClass:[NSArray class]] || ![right isKindOfClass:[NSArray class]]) return NO;
        NSArray *a = left, *b = right;
        if (a.count != b.count) return NO;
        for (NSUInteger i = 0; i < a.count; i++) if (!AQJSONEqual(a[i], b[i])) return NO;
        return YES;
    }
    if ([left isKindOfClass:[NSDictionary class]] || [right isKindOfClass:[NSDictionary class]]) {
        if (![left isKindOfClass:[NSDictionary class]] || ![right isKindOfClass:[NSDictionary class]]) return NO;
        NSDictionary *a = left, *b = right;
        if (a.count != b.count) return NO;
        for (id key in a) if (!AQJSONEqual(a[key], b[key])) return NO;
        return YES;
    }
    return left == [NSNull null] && right == [NSNull null];
}

static NSComparisonResult AQCompareUTF8(NSString *left, NSString *right) {
    NSData *leftData = [left dataUsingEncoding:NSUTF8StringEncoding];
    NSData *rightData = [right dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger common = MIN(leftData.length, rightData.length);
    int result = memcmp(leftData.bytes, rightData.bytes, common);
    if (result < 0) return NSOrderedAscending;
    if (result > 0) return NSOrderedDescending;
    if (leftData.length < rightData.length) return NSOrderedAscending;
    if (leftData.length > rightData.length) return NSOrderedDescending;
    return NSOrderedSame;
}

static NSArray<NSString *> *AQSortedStrings(NSSet<NSString *> *values) {
    return [values.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        return AQCompareUTF8(left, right);
    }];
}

static NSDictionary *AQManifest(NSData *data, NSError **error) {
    NSDictionary *manifest = AQParseObject(data, error);
    if (!manifest) return nil;
    manifest = AQObjectFields(manifest, @[@"schema_version", @"source_authority", @"plan_sha256",
        @"rules_sha256", @"coverage_mode", @"selected_fixture_ids", @"fixtures"], @[], error);
    if (!manifest || !AQNumberVersion(manifest[@"schema_version"], 2, error)) return nil;
    if (![manifest[@"source_authority"] isKindOfClass:[NSString class]] ||
        ![manifest[@"source_authority"] isEqualToString:AQSourceAuthority] ||
        !AQDigestValue(manifest[@"plan_sha256"], error) ||
        !AQDigestValue(manifest[@"rules_sha256"], error)) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    NSString *coverage = AQText(manifest[@"coverage_mode"], 4096, error);
    if (!coverage || !([coverage isEqualToString:@"mandatory_full_plan"] ||
                       [coverage isEqualToString:@"authorized_partial_plan"])) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }

    NSArray *selectedValues = AQArrayValue(manifest[@"selected_fixture_ids"], YES, error);
    if (!selectedValues) return nil;
    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    NSMutableSet<NSString *> *foldedSelected = [NSMutableSet set];
    for (id item in selectedValues) {
        NSString *identifier = AQIdentifier(item, error);
        NSString *folded = identifier ? AQFold(identifier) : nil;
        if (!identifier || [foldedSelected containsObject:folded]) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        [selected addObject:identifier];
        [foldedSelected addObject:folded];
    }

    NSArray *fixtureValues = AQArrayValue(manifest[@"fixtures"], YES, error);
    if (!fixtureValues) return nil;
    NSMutableArray<NSDictionary *> *fixtures = [NSMutableArray array];
    for (id item in fixtureValues) {
        NSDictionary *fixture = AQValidatedFixture(item, YES, NULL, NULL, error);
        if (!fixture) return nil;
        [fixtures addObject:fixture];
    }
    if (fixtures.count != selected.count) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    for (NSUInteger i = 0; i < fixtures.count; i++) {
        if (![(NSString *)fixtures[i][@"fixture_id"] isEqualToString:selected[i]]) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
    }

    NSMutableDictionary<NSString *, NSNumber *> *groupOrders = [NSMutableDictionary dictionary];
    for (NSDictionary *fixture in fixtures) {
        NSString *group = fixture[@"group_id"];
        NSNumber *order = fixture[@"order"];
        NSNumber *previous = groupOrders[group];
        if (previous != nil && order.longLongValue <= previous.longLongValue) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        groupOrders[group] = order;
    }
    return manifest;
}

static NSDictionary *AQValidateSnapshotContractBody(NSData *manifestData, NSArray *oracles,
                                                     NSArray *evidence,
                                                     NSString *authorizedManifestSHA256,
                                                     NSString *authorizedPlanSHA256,
                                                     NSString *authorizedRulesSHA256,
                                                     NSError **error) {
    if (![manifestData isKindOfClass:[NSData class]] || ![oracles isKindOfClass:[NSArray class]] ||
        ![evidence isKindOfClass:[NSArray class]] ||
        ![authorizedManifestSHA256 isKindOfClass:[NSString class]] ||
        ![authorizedPlanSHA256 isKindOfClass:[NSString class]] ||
        ![authorizedRulesSHA256 isKindOfClass:[NSString class]] ||
        oracles.count + evidence.count > AQMaximumGraphRecords) {
        AQContractErrorCode code = oracles.count + evidence.count > AQMaximumGraphRecords &&
            [oracles isKindOfClass:[NSArray class]] && [evidence isKindOfClass:[NSArray class]]
            ? AQLimitExceeded : AQInputInvalid;
        AQFailContract(error, code);
        return nil;
    }

    NSDictionary *manifest = AQManifest(manifestData, error);
    if (!manifest) return nil;
    NSString *manifestDigest = AQDigest(@"", manifest, error);
    if (!manifestDigest || !AQDigestValue(authorizedManifestSHA256, error) ||
        !AQDigestValue(authorizedPlanSHA256, error) || !AQDigestValue(authorizedRulesSHA256, error)) return nil;
    if (![manifestDigest isEqualToString:authorizedManifestSHA256] ||
        ![(NSString *)manifest[@"plan_sha256"] isEqualToString:authorizedPlanSHA256] ||
        ![(NSString *)manifest[@"rules_sha256"] isEqualToString:authorizedRulesSHA256]) {
        AQFailContract(error, AQPinMismatch);
        return nil;
    }

    NSDictionary<NSString *, NSDictionary *> *oracleRecords = AQRegistry(oracles, @"oracle", error);
    if (!oracleRecords) return nil;
    NSDictionary<NSString *, NSDictionary *> *evidenceRecords = AQRegistry(evidence, @"evidence", error);
    if (!evidenceRecords) return nil;

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *adjacency = [NSMutableDictionary dictionary];
    for (NSString *reference in evidenceRecords) {
        NSMutableArray<NSString *> *dependencies = [NSMutableArray array];
        for (NSDictionary *pin in evidenceRecords[reference][@"evidence_refs"]) {
            [dependencies addObject:(NSString *)pin[@"evidence_ref"]];
        }
        adjacency[reference] = [dependencies copy];
    }

    NSMutableSet<NSString *> *usedOracles = [NSMutableSet set];
    NSMutableSet<NSString *> *usedEvidence = [NSMutableSet set];
    NSMutableArray<NSArray<NSDictionary *> *> *selections = [NSMutableArray array];
    for (NSDictionary *fixture in manifest[@"fixtures"]) {
        NSDictionary *oraclePin = fixture[@"oracle_pin"];
        NSString *oracleReference = oraclePin[@"oracle_ref"];
        NSDictionary *oracle = oracleRecords[oracleReference];
        if (oracle == nil) {
            AQFailContract(error, AQMissingReference);
            return nil;
        }
        [usedOracles addObject:oracleReference];
        if (!AQCheckPin(oraclePin, oracle, @"oracle", error)) return nil;

        NSDictionary *binding = AQFixtureBinding(fixture);
        NSString *expectedLabel = [oracle[@"corpus_origin"] isEqualToString:@"synthetic"]
            ? @"synthetic_expectation_v2" : @"independent_reference_pinned_v1";
        if (!AQJSONEqual(binding, oracle[@"fixture"]) ||
        ![(NSString *)oracle[@"acceptance_rule_sha256"] isEqualToString:
          (NSString *)manifest[@"rules_sha256"]] ||
            ![(NSString *)fixture[@"identity_evidence"] isEqualToString:expectedLabel]) {
            AQFailContract(error, AQEvidenceConflict);
            return nil;
        }

        NSMutableArray<NSString *> *roots = [NSMutableArray array];
    for (NSDictionary *pin in oracle[@"evidence_refs"]) {
        [roots addObject:(NSString *)pin[@"evidence_ref"]];
    }
        NSSet<NSString *> *reachable = AQWalkGraph(roots, adjacency, YES, error);
        if (!reachable) return nil;
        [usedEvidence unionSet:reachable];

        NSMutableArray<NSDictionary *> *closure = [NSMutableArray arrayWithObject:oracle];
        for (NSString *reference in AQSortedStrings(reachable)) {
        NSDictionary *record = evidenceRecords[reference];
        if (record == nil) {
            AQFailContract(error, AQMissingReference);
            return nil;
        }
        [closure addObject:record];
        }
        for (NSDictionary *item in closure) {
            for (NSString *key in @[@"fixture", @"corpus_origin", @"acceptance_rule_sha256"]) {
                if (!AQJSONEqual(item[key], oracle[key])) {
                    AQFailContract(error, AQEvidenceConflict);
                    return nil;
                }
            }
            for (NSDictionary *dependency in item[@"evidence_refs"]) {
        NSDictionary *target = evidenceRecords[(NSString *)dependency[@"evidence_ref"]];
        if (target == nil) {
            AQFailContract(error, AQMissingReference);
            return nil;
        }
                if (!AQCheckPin(dependency, target, @"evidence", error)) return nil;
            }
        }
        [selections addObject:@[fixture, oracle]];
    }

    if (![usedOracles isEqualToSet:[NSSet setWithArray:oracleRecords.allKeys]] ||
        ![usedEvidence isEqualToSet:[NSSet setWithArray:evidenceRecords.allKeys]]) {
        AQFailContract(error, AQUnusedRecord);
        return nil;
    }

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *sourcePins = [NSMutableDictionary dictionary];
    for (NSString *reference in AQSortedStrings(usedEvidence)) {
        NSDictionary *record = evidenceRecords[reference];
        NSDictionary *external = record[@"reference"];
        if (external == nil) continue;
        NSString *externalReference = external[@"ref"];
        NSString *externalRevision = external[@"revision"];
        NSString *externalSHA256 = external[@"sha256"];
        if (externalReference == nil || externalRevision == nil || externalSHA256 == nil) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        NSArray<NSString *> *identity = @[externalRevision, externalSHA256];
        NSArray<NSString *> *existing = sourcePins[externalReference];
        if (existing != nil && ![existing isEqualToArray:identity]) {
            AQFailContract(error, AQEvidenceConflict);
            return nil;
        }
        sourcePins[externalReference] = identity;
    }

    NSMutableArray<NSDictionary *> *assessments = [NSMutableArray array];
    for (NSArray<NSDictionary *> *selection in selections) {
        NSDictionary *fixture = selection[0], *oracle = selection[1];
        NSString *origin = oracle[@"corpus_origin"];
        NSDictionary *oraclePin = fixture[@"oracle_pin"];
        NSString *fixtureID = fixture[@"fixture_id"];
        NSString *oracleReference = oracle[@"oracle_ref"];
        NSString *oracleRevision = oracle[@"revision"];
        NSString *oracleSHA256 = oraclePin[@"sha256"];
        if (origin == nil || oraclePin == nil || fixtureID == nil ||
            oracleReference == nil || oracleRevision == nil || oracleSHA256 == nil) {
            AQFailContract(error, AQInputInvalid);
            return nil;
        }
        NSString *support = [origin isEqualToString:@"synthetic"] ? @"synthetic_only"
            : @"pinned_unverified";
        [assessments addObject:@{
            @"fixture_id": fixtureID,
            @"oracle_ref": oracleReference,
            @"oracle_revision": oracleRevision,
            @"oracle_sha256": oracleSHA256,
            @"corpus_origin": origin,
            @"byte_integrity": @"not_checked",
            @"structural_expectation": @"validated",
            @"independent_support": support,
            @"owner_approval": @"not_checked",
        }];
    }
    return @{
        @"manifest_sha256": manifestDigest,
        @"source_authority": AQSourceAuthority,
        @"fixtures": [assessments copy],
    };
}

NSDictionary *AQValidateSnapshotContract(NSData *manifest, NSArray<NSData *> *oracles,
                                         NSArray<NSData *> *evidence,
                                         NSString *authorizedManifestSHA256,
                                         NSString *authorizedPlanSHA256,
                                         NSString *authorizedRulesSHA256, NSError **error) {
    if (error) *error = nil;
    NSDictionary *result = nil;
    @try {
        result = AQValidateSnapshotContractBody(manifest, oracles, evidence,
            authorizedManifestSHA256, authorizedPlanSHA256, authorizedRulesSHA256, error);
    } @catch (__unused NSException *exception) {
        AQFailContract(error, AQInputInvalid);
        return nil;
    }
    if (result == nil && error != NULL && *error == nil) AQFailContract(error, AQInputInvalid);
    return result;
}
