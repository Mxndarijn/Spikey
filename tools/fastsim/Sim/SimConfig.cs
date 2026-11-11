namespace FastSim;

/// Port of sim/sim_config.gd (generated from it; keep in step).
public static class SimConfig
{
    public const long GAMEPLAY_VERSION = 20;
    public const long MAX_REVIVES = 1;
    public const long TICKS_PER_SECOND = 60;
    public const long SUB = 64;
    public const long WORLD_W = 360 * SUB;
    public const long WORLD_H = 640 * SUB;
    public const long BIRD_RADIUS = 14 * SUB;
    public const long BIRD_START_X = 180 * SUB;
    public const long BIRD_START_Y = 300 * SUB;
    public const long SPEED_X = 4 * SUB;
    public const long GRAVITY = 13;
    public const long FLAP_VY = -5 * SUB;
    public const long MAX_FALL_VY = 12 * SUB;
    public const long KILL_TOP = 34 * SUB;
    public const long KILL_BOTTOM = 606 * SUB;
    public const long SLOT_TOP = 60 * SUB;
    public const long SLOT_SIZE = 40 * SUB;
    public const long SLOT_COUNT = 13;
    public const long SPIKE_DEPTH = 26 * SUB;
    public const long SPIKE_HALF_BASE = 15 * SUB;
    public const long POINTS_PER_ROOM = 10;
    public const long BASE_SPIKES = 2;
    public const long POINTS_PER_EXTRA_SPIKE = 6;
    public const long MAX_SPIKES = 8;
    public const long COIN_RADIUS = 12 * SUB;
    public const long COIN_MIN_X = 80 * SUB;
    public const long COIN_MAX_X = 280 * SUB;
    public const long COIN_MIN_Y = 90 * SUB;
    public const long COIN_MAX_Y = 550 * SUB;
    public const long EXIT_HALF = 48 * SUB;
    public const long EXIT_FIT = 2 * SLOT_SIZE - SPIKE_HALF_BASE;
    public const long EXIT_MIN_Y = 110 * SUB;
    public const long EXIT_MAX_Y = 530 * SUB;
    public const long FORK_SPLIT_Y = 320 * SUB;
    public const long FORK_EVERY = 50;
    public const long WILD_COINS = 3;
    public const long ARRIVAL_HOLD = 60;
    public const long ARRIVAL_BLIND = 60;
    public const long ARRIVAL_FOLLOW = 120;
    public const long ARRIVAL_TRIES = 16;
    public const long ARRIVAL_EDGE = 84 * SUB;
    public const long MAX_TICKS = 60 * 60 * 30;

    public static long slot_center_y(long slot) => SLOT_TOP + slot * SLOT_SIZE + SLOT_SIZE / 2;
}
