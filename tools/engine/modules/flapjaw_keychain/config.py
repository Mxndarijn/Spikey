# Flapjaw's Keychain module: only the iOS engine has it (services/supabase_client.gd).


def can_build(env, platform):
    return platform == "ios"


def configure(env):
    pass
