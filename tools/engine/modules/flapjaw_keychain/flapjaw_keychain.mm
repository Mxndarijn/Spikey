#include "flapjaw_keychain.h"

#include "core/object/class_db.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSString *const FLAPJAW_SERVICE = @"flapjaw";

static NSString *to_ns(const String &p_text) {
	NSString *s = [NSString stringWithUTF8String:p_text.utf8().get_data()];
	return s != nil ? s : @"";
}

// The query that finds one value.
static NSMutableDictionary *item_query(const String &p_name) {
	return [@{
		(__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService : FLAPJAW_SERVICE,
		(__bridge id)kSecAttrAccount : to_ns(p_name),
	} mutableCopy];
}

void FlapjawKeychain::_bind_methods() {
	ClassDB::bind_method(D_METHOD("read", "name"), &FlapjawKeychain::read);
	ClassDB::bind_method(D_METHOD("write", "name", "value"), &FlapjawKeychain::write);
}

String FlapjawKeychain::read(const String &p_name) const {
	NSMutableDictionary *query = item_query(p_name);
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status != errSecSuccess || result == NULL) {
		return String();
	}
	NSData *data = (__bridge_transfer NSData *)result;
	return String::utf8((const char *)data.bytes, (int)data.length);
}

bool FlapjawKeychain::write(const String &p_name, const String &p_value) {
	NSData *data = [to_ns(p_value) dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *changes = @{
		(__bridge id)kSecValueData : data,
		(__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
	};
	NSMutableDictionary *query = item_query(p_name);
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)changes);
	if (status == errSecItemNotFound) {
		[query addEntriesFromDictionary:changes];
		status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	}
	return status == errSecSuccess;
}
