#import "AQJSON.h"
#import <CommonCrypto/CommonDigest.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>

NSString * const AQContractErrorDomain = @"org.argus.fixture-contract";
// The default parser and encoder remain capped at 64 KiB. Explicitly bounded
// protocol callers may select up to 12 MiB; canonicalization applies the same
// selected bound to its output. Decoded Objective-C object storage is
// separate from the input and canonical output byte buffers.
static const NSUInteger AQMaximumBytes = 65536;
static const NSUInteger AQMaximumExtendedBytes = 12 * 1024 * 1024;
static const NSUInteger AQMaximumDepth = 32;

NSError *AQContractError(AQContractErrorCode code) {
    NSArray *names = @[@"INPUT_INVALID", @"LIMIT_EXCEEDED", @"SCHEMA_UNSUPPORTED", @"PIN_MISMATCH",
        @"MISSING_REFERENCE", @"REFERENCE_CYCLE", @"EVIDENCE_CONFLICT", @"UNUSED_RECORD"];
    if (code < AQInputInvalid || code > AQUnusedRecord) code = AQInputInvalid;
    return [NSError errorWithDomain:AQContractErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey:names[code - 1]}];
}

static BOOL AQFail(NSError **error, AQContractErrorCode code) {
    if (error) *error = AQContractError(code);
    return NO;
}

static BOOL AQASCII(NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++) if ([text characterAtIndex:i] > 127) return NO;
    return YES;
}

static BOOL AQValidString(NSString *text) {
    // Explicit scalar checking avoids NSString's possible lossy surrogate output.
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= 0xd800 && c <= 0xdbff) {
            if (++i >= text.length) return NO;
            unichar low = [text characterAtIndex:i];
            if (low < 0xdc00 || low > 0xdfff) return NO;
        } else if (c >= 0xdc00 && c <= 0xdfff) return NO;
    }
    return [text isEqualToString:text.precomposedStringWithCanonicalMapping];
}

/** A byte parser owns all tokenization; duplicate keys cannot be discarded by
 * NSJSONSerialization, and signed integers never pass through floating point.
 */
typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger position;
    AQContractErrorCode failure;
} AQJSONReader;

static void AQWhitespace(AQJSONReader *r) {
    while (r->position < r->length) {
        uint8_t c = r->bytes[r->position];
        if (c != ' ' && c != '\t' && c != '\n' && c != '\r') break;
        r->position++;
    }
}

static BOOL AQConsume(AQJSONReader *r, uint8_t expected) {
    if (r->position == r->length || r->bytes[r->position] != expected) return NO;
    r->position++;
    return YES;
}

static BOOL AQHexUnit(AQJSONReader *r, uint32_t *unit) {
    if (r->length - r->position < 4) return NO;
    uint32_t value = 0;
    for (NSUInteger i = 0; i < 4; i++) {
        uint8_t c = r->bytes[r->position++];
        uint32_t digit;
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'f') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') digit = c - 'A' + 10;
        else return NO;
        value = (value << 4) | digit;
    }
    *unit = value;
    return YES;
}

static NSString *AQReadString(AQJSONReader *r) {
    if (!AQConsume(r, '"')) return nil;
    NSMutableData *utf8 = [NSMutableData data];
    while (r->position < r->length) {
        uint8_t c = r->bytes[r->position++];
        if (c == '"') {
            NSString *text = [[NSString alloc] initWithData:utf8 encoding:NSUTF8StringEncoding];
            return text && AQValidString(text) ? text : nil;
        }
        if (c < 0x20) return nil;
        if (c != '\\') { [utf8 appendBytes:&c length:1]; continue; }
        if (r->position == r->length) return nil;
        c = r->bytes[r->position++];
        switch (c) {
            case '"': case '\\': case '/': break;
            case 'b': c = 8; break;
            case 'f': c = 12; break;
            case 'n': c = 10; break;
            case 'r': c = 13; break;
            case 't': c = 9; break;
            case 'u': {
                uint32_t scalar, low;
                if (!AQHexUnit(r, &scalar)) return nil;
                if (scalar >= 0xd800 && scalar <= 0xdbff) {
                    if (!AQConsume(r, '\\') || !AQConsume(r, 'u') || !AQHexUnit(r, &low) || low < 0xdc00 || low > 0xdfff) return nil;
                    scalar = 0x10000 + ((scalar - 0xd800) << 10) + low - 0xdc00;
                } else if (scalar >= 0xdc00 && scalar <= 0xdfff) return nil;
                uint8_t bytes[4]; NSUInteger count;
                if (scalar < 0x80) { bytes[0] = (uint8_t)scalar; count = 1; }
                else if (scalar < 0x800) {
                    bytes[0] = 0xc0 | (scalar >> 6); bytes[1] = 0x80 | (scalar & 63); count = 2;
                } else if (scalar < 0x10000) {
                    bytes[0] = 0xe0 | (scalar >> 12); bytes[1] = 0x80 | ((scalar >> 6) & 63); bytes[2] = 0x80 | (scalar & 63); count = 3;
                } else {
                    bytes[0] = 0xf0 | (scalar >> 18); bytes[1] = 0x80 | ((scalar >> 12) & 63);
                    bytes[2] = 0x80 | ((scalar >> 6) & 63); bytes[3] = 0x80 | (scalar & 63); count = 4;
                }
                [utf8 appendBytes:bytes length:count];
                continue;
            }
            default: return nil;
        }
        [utf8 appendBytes:&c length:1];
    }
    return nil;
}

static NSNumber *AQReadInteger(AQJSONReader *r) {
    BOOL negative = AQConsume(r, '-');
    if (r->position == r->length) return nil;
    uint8_t first = r->bytes[r->position];
    if (first < '0' || first > '9') return nil;
    const uint64_t limit = negative ? (UINT64_C(1) << 63) : INT64_MAX;
    uint64_t magnitude = 0;
    NSUInteger count = 0;
    while (r->position < r->length) {
        uint8_t c = r->bytes[r->position];
        if (c < '0' || c > '9') break;
        uint64_t digit = c - '0';
        if (magnitude > (limit - digit) / 10) return nil;
        magnitude = magnitude * 10 + digit;
        r->position++; count++;
    }
    if ((count > 1 && first == '0') || (negative && magnitude == 0)) return nil;
    int64_t value = negative ? (magnitude == (UINT64_C(1) << 63) ? INT64_MIN : -(int64_t)magnitude) : (int64_t)magnitude;
    return [NSNumber numberWithLongLong:value];
}

static id AQReadValue(AQJSONReader *r, NSUInteger depth) {
    if (depth > AQMaximumDepth) { r->failure = AQLimitExceeded; return nil; }
    AQWhitespace(r);
    if (r->position == r->length) return nil;
    uint8_t c = r->bytes[r->position];
    if (c == '"') return AQReadString(r);
    if (c == '{') {
        r->position++; AQWhitespace(r);
        NSMutableDictionary *object = [NSMutableDictionary dictionary];
        if (AQConsume(r, '}')) return [object copy];
        while (YES) {
            NSString *key = AQReadString(r);
            if (!key || !AQASCII(key) || object[key] != nil) return nil;
            AQWhitespace(r);
            if (!AQConsume(r, ':')) return nil;
            id value = AQReadValue(r, depth + 1);
            if (!value) return nil;
            object[key] = value;
            AQWhitespace(r);
            if (AQConsume(r, '}')) return [object copy];
            if (!AQConsume(r, ',')) return nil;
            AQWhitespace(r);
        }
    }
    if (c == '[') {
        r->position++; AQWhitespace(r);
        NSMutableArray *array = [NSMutableArray array];
        if (AQConsume(r, ']')) return [array copy];
        while (YES) {
            id value = AQReadValue(r, depth + 1);
            if (!value) return nil;
            [array addObject:value]; AQWhitespace(r);
            if (AQConsume(r, ']')) return [array copy];
            if (!AQConsume(r, ',')) return nil;
        }
    }
    const char *literal = c == 't' ? "true" : c == 'f' ? "false" : c == 'n' ? "null" : NULL;
    if (literal) {
        size_t count = strlen(literal);
        if (r->length - r->position < count || memcmp(r->bytes + r->position, literal, count)) return nil;
        r->position += count;
        return c == 't' ? @YES : c == 'f' ? @NO : [NSNull null];
    }
    return AQReadInteger(r);
}

static BOOL AQAppend(NSMutableData *output, const void *bytes, NSUInteger length,
                     NSUInteger maximumBytes, NSError **error) {
    if (output.length > maximumBytes || length > maximumBytes - output.length)
        return AQFail(error, AQLimitExceeded);
    [output appendBytes:bytes length:length];
    return YES;
}

static BOOL AQWriteString(NSString *value, NSMutableData *output,
                          NSUInteger maximumBytes, NSError **error) {
    if (!AQValidString(value)) return AQFail(error, AQInputInvalid);
    // UTF-16 length is a lower bound on valid UTF-8 length; bound allocation too.
    if (value.length > maximumBytes) return AQFail(error, AQLimitExceeded);
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    if (!data) return AQFail(error, AQInputInvalid);
    if (!AQAppend(output, "\"", 1, maximumBytes, error)) return NO;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        uint8_t c = bytes[i];
        const char *escape = NULL;
        switch (c) {
            case '"': escape = "\\\""; break;
            case '\\': escape = "\\\\"; break;
            case 8: escape = "\\b"; break;
            case 9: escape = "\\t"; break;
            case 10: escape = "\\n"; break;
            case 12: escape = "\\f"; break;
            case 13: escape = "\\r"; break;
        }
        if (escape) { if (!AQAppend(output, escape, 2, maximumBytes, error)) return NO; }
        else if (c < 0x20) {
            const char *hex = "0123456789abcdef";
            char escaped[] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15]};
            if (!AQAppend(output, escaped, 6, maximumBytes, error)) return NO;
        } else if (!AQAppend(output, &c, 1, maximumBytes, error)) return NO;
    }
    return AQAppend(output, "\"", 1, maximumBytes, error);
}

static BOOL AQWriteValue(id value, NSUInteger depth, NSMutableData *output,
                         NSUInteger maximumBytes, NSError **error) {
    if (depth > AQMaximumDepth) return AQFail(error, AQLimitExceeded);
    if ([value isKindOfClass:[NSString class]])
        return AQWriteString(value, output, maximumBytes, error);
    if (value == [NSNull null]) return AQAppend(output, "null", 4, maximumBytes, error);
    if ([value isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
            return [value boolValue] ? AQAppend(output, "true", 4, maximumBytes, error) :
                AQAppend(output, "false", 5, maximumBytes, error);
        const char *type = [value objCType];
        if (strlen(type) != 1 || !strchr("cCsSiIlLqQ", type[0])) return AQFail(error, AQInputInvalid);
        if (strchr("CSILQ", type[0]) && [value unsignedLongLongValue] > INT64_MAX) return AQFail(error, AQInputInvalid);
        char digits[32];
        int count = snprintf(digits, sizeof(digits), "%lld", [value longLongValue]);
        return AQAppend(output, digits, (NSUInteger)count, maximumBytes, error);
    }
    if ([value isKindOfClass:[NSArray class]]) {
        if (!AQAppend(output, "[", 1, maximumBytes, error)) return NO;
        BOOL first = YES;
        for (id item in value) {
            if (!first && !AQAppend(output, ",", 1, maximumBytes, error)) return NO;
            first = NO;
            if (!AQWriteValue(item, depth + 1, output, maximumBytes, error)) return NO;
        }
        return AQAppend(output, "]", 1, maximumBytes, error);
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *object = value;
        for (id key in object) if (![key isKindOfClass:[NSString class]] || !AQASCII(key)) return AQFail(error, AQInputInvalid);
        NSArray *keys = [object.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [a compare:b options:NSLiteralSearch];
        }];
        if (!AQAppend(output, "{", 1, maximumBytes, error)) return NO;
        BOOL first = YES;
        for (NSString *key in keys) {
            if (!first && !AQAppend(output, ",", 1, maximumBytes, error)) return NO;
            first = NO;
            if (!AQWriteString(key, output, maximumBytes, error) ||
                !AQAppend(output, ":", 1, maximumBytes, error) ||
                !AQWriteValue(object[key], depth + 1, output, maximumBytes, error)) return NO;
        }
        return AQAppend(output, "}", 1, maximumBytes, error);
    }
    return AQFail(error, AQInputInvalid);
}

NSData *AQCanonicalJSON(id value, NSError **error) {
    return AQCanonicalJSONWithMaximumBytes(value, AQMaximumBytes, error);
}

NSData *AQCanonicalJSONWithMaximumBytes(id value, NSUInteger maximumBytes, NSError **error) {
    if (error) *error = nil;
    if (maximumBytes == 0 || maximumBytes > AQMaximumExtendedBytes) {
        AQFail(error, AQLimitExceeded);
        return nil;
    }
    NSMutableData *output = [NSMutableData data];
    return AQWriteValue(value, 0, output, maximumBytes, error) ? [output copy] : nil;
}

id AQParseJSON(NSData *data, NSError **error) {
    return AQParseJSONWithMaximumBytes(data, AQMaximumBytes, error);
}

id AQParseJSONWithMaximumBytes(NSData *data, NSUInteger maximumBytes, NSError **error) {
    if (error) *error = nil;
    if (maximumBytes == 0 || maximumBytes > AQMaximumExtendedBytes) {
        AQFail(error, AQLimitExceeded);
        return nil;
    }
    if (![data isKindOfClass:[NSData class]]) { AQFail(error, AQInputInvalid); return nil; }
    if (data.length > maximumBytes) { AQFail(error, AQLimitExceeded); return nil; }
    AQJSONReader reader = {data.bytes, data.length, 0, AQInputInvalid};
    id value = AQReadValue(&reader, 0);
    AQWhitespace(&reader);
    if (![value isKindOfClass:[NSDictionary class]] || reader.position != reader.length) {
        AQFail(error, reader.failure); return nil;
    }
    // Input whitespace/escapes need not be canonical. The canonical form must
    // independently fit the byte limit (raw controls can grow when encoded).
    return AQCanonicalJSONWithMaximumBytes(value, maximumBytes, error) ? value : nil;
}

NSString *AQDigest(NSString *domain, id value, NSError **error) {
    if (error) *error = nil;
    if (![domain isKindOfClass:[NSString class]] || !AQASCII(domain)) { AQFail(error, AQInputInvalid); return nil; }
    NSData *canonical = AQCanonicalJSON(value, error);
    if (!canonical) return nil;
    NSMutableData *input = [NSMutableData data];
    if (domain.length) {
        NSData *domainData = [domain dataUsingEncoding:NSASCIIStringEncoding];
        if (domainData == nil) { AQFail(error, AQInputInvalid); return nil; }
        [input appendData:domainData];
        uint8_t zero = 0; [input appendBytes:&zero length:1];
    }
    [input appendData:canonical];
    if (input.length > UINT32_MAX) { AQFail(error, AQLimitExceeded); return nil; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
    char hex[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        hex[2*i] = "0123456789abcdef"[digest[i] >> 4];
        hex[2*i+1] = "0123456789abcdef"[digest[i] & 15];
    }
    hex[sizeof(hex)-1] = 0;
    return [NSString stringWithUTF8String:hex];
}
