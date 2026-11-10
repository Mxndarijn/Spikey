#pragma once

#include "core/object/object.h"

// The engine singleton "FlapjawKeychain" (iOS only): small text values in the iOS Keychain,
// which keeps them when the app is uninstalled and reinstalled (app files do not survive
// that). Each value is a generic password under the service "flapjaw", readable after the
// phone's first unlock since it started.
// The methods are read/write, not get/set: those would hide Object.get and Object.set.
class FlapjawKeychain : public Object {
	GDCLASS(FlapjawKeychain, Object)

protected:
	static void _bind_methods();

public:
	// The value saved under p_name, or "" when there is none (or the Keychain says no).
	String read(const String &p_name) const;
	// Saves p_value under p_name, replacing any old value. Whether the Keychain took it.
	bool write(const String &p_name, const String &p_value);
};
