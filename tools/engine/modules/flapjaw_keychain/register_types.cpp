#include "register_types.h"

#include "flapjaw_keychain.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"

static FlapjawKeychain *keychain = nullptr;

void initialize_flapjaw_keychain_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_ABSTRACT_CLASS(FlapjawKeychain);
	keychain = memnew(FlapjawKeychain);
	Engine::get_singleton()->add_singleton(Engine::Singleton("FlapjawKeychain", keychain));
}

void uninitialize_flapjaw_keychain_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE || keychain == nullptr) {
		return;
	}
	Engine::get_singleton()->remove_singleton("FlapjawKeychain");
	memdelete(keychain);
	keychain = nullptr;
}
